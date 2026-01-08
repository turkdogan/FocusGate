//
//  SystemExtensionManager.swift
//  FocusGate
//
//  Manages system extension installation and activation
//

import Foundation
import SystemExtensions

class SystemExtensionManager: NSObject, OSSystemExtensionRequestDelegate {
    static let shared = SystemExtensionManager()

    private var completionHandler: ((Bool, Error?) -> Void)?

    func installExtension(completion: @escaping (Bool, Error?) -> Void) {
        self.completionHandler = completion

        let extensionIdentifier = "dev.turkdogan.FocusGate.Extension"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)

        print("🔧 Requesting system extension installation: \(extensionIdentifier)")
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        print("✅ System extension request finished with result: \(result.rawValue)")
        completionHandler?(true, nil)
        completionHandler = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        print("❌ System extension request failed: \(error.localizedDescription)")
        completionHandler?(false, error)
        completionHandler = nil
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("⚠️ System extension requires user approval in System Settings")
        // User needs to approve in System Settings > General > Login Items & Extensions
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        print("🔄 Replacing existing extension")
        return .replace
    }
}
