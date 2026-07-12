//
//  SystemExtensionManager.swift
//  FocusGate
//
//  Activates the bundled FocusGateExtension system extension via OSSystemExtensionRequest
//

import Combine
import Foundation
import SystemExtensions
import os.log

final class SystemExtensionManager: NSObject, ObservableObject {
    static let extensionBundleID = "dev.turkdogan.FocusGate.FocusGateExtension"

    enum ActivationState: Equatable {
        case idle
        case requesting
        case needsUserApproval
        case activated
        case needsReboot
        case failed(String)
    }

    @Published private(set) var state: ActivationState = .idle

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "SystemExtensionManager")
    private var continuation: CheckedContinuation<Void, Error>?

    /// Requests activation of the embedded system extension. Suspends until the
    /// system reports the extension activated (or replaced), which may include
    /// waiting for the user to approve it in System Settings.
    func activate() async throws {
        if case .requesting = state { return }
        if case .needsUserApproval = state { return }

        os_log("🚀 Submitting system extension activation request", log: logger, type: .info)
        setState(.requesting)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: Self.extensionBundleID,
                queue: .main
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    /// Deactivates (uninstalls) the system extension. Not used by the normal
    /// disable flow — turning the filter off only disables the NEFilterManager
    /// configuration — but exposed for a full uninstall.
    func deactivate() async throws {
        os_log("🗑️ Submitting system extension deactivation request", log: logger, type: .info)
        setState(.requesting)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: Self.extensionBundleID,
                queue: .main
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private func setState(_ newState: ActivationState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { self.state = newState }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        os_log("♻️ Replacing existing extension %{public}@ with %{public}@",
               log: logger, type: .info,
               existing.bundleShortVersion, ext.bundleShortVersion)
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("⏳ Extension needs user approval in System Settings", log: logger, type: .info)
        setState(.needsUserApproval)
        // Do not resume the continuation — the request stays pending until the
        // user approves or denies, and didFinish/didFail fires afterwards.
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            os_log("✅ System extension activated", log: logger, type: .info)
            setState(.activated)
            finish(.success(()))
        case .willCompleteAfterReboot:
            os_log("🔄 System extension will activate after reboot", log: logger, type: .info)
            setState(.needsReboot)
            finish(.success(()))
        @unknown default:
            os_log("⚠️ Unknown activation result: %d", log: logger, type: .error, result.rawValue)
            setState(.activated)
            finish(.success(()))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        os_log("❌ System extension request failed: %{public}@",
               log: logger, type: .error, error.localizedDescription)
        setState(.failed(error.localizedDescription))
        finish(.failure(error))
    }
}
