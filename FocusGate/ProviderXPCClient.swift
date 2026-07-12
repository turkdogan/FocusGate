//
//  ProviderXPCClient.swift
//  FocusGate
//
//  Connects to the filter extension's mach service to fetch the
//  activity feed. See XPCProtocol.swift for the contract.
//

import Foundation
import os.log

final class ProviderXPCClient {
    static let shared = ProviderXPCClient()

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "ProviderXPCClient")
    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "dev.turkdogan.FocusGate.xpcclient")

    private func currentConnection() -> NSXPCConnection {
        queue.sync {
            if let existing = connection { return existing }

            // The extension runs as root, so its mach service lives in the
            // privileged bootstrap namespace, not the user session.
            let new = NSXPCConnection(machServiceName: FocusGateXPC.serviceName, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: ProviderCommunication.self)
            new.invalidationHandler = { [weak self] in
                self?.queue.async { self?.connection = nil }
            }
            new.interruptionHandler = { [weak self] in
                self?.queue.async { self?.connection = nil }
            }
            new.resume()
            connection = new
            return new
        }
    }

    private func proxy(onError: @escaping () -> Void) -> ProviderCommunication? {
        let raw = currentConnection().remoteObjectProxyWithErrorHandler { [weak self] error in
            os_log("XPC call failed: %{public}@", log: self?.logger ?? .default,
                   type: .error, error.localizedDescription)
            onError()
        }
        return raw as? ProviderCommunication
    }

    /// Fetches recent decisions from the provider. Completion is called on
    /// the main queue; an unreachable extension yields an empty array.
    func fetchRecentDecisions(since: Date = .distantPast,
                              completion: @escaping ([DecisionLogEntry]) -> Void) {
        let finish: ([DecisionLogEntry]) -> Void = { entries in
            DispatchQueue.main.async { completion(entries) }
        }

        guard let proxy = proxy(onError: { finish([]) }) else {
            finish([])
            return
        }

        proxy.fetchRecentDecisions(sinceTimestamp: since.timeIntervalSince1970) { data in
            let entries = (try? JSONDecoder().decode([DecisionLogEntry].self, from: data)) ?? []
            finish(entries)
        }
    }

    func clearDecisions(completion: @escaping (Bool) -> Void = { _ in }) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }

        guard let proxy = proxy(onError: { finish(false) }) else {
            finish(false)
            return
        }

        proxy.clearDecisions { finish($0) }
    }

    /// Pushes the configuration to the running provider so changes (pause,
    /// blocklist edits) apply immediately instead of on next restart.
    func updateConfiguration(_ data: Data, completion: @escaping (Bool) -> Void = { _ in }) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }

        guard let proxy = proxy(onError: { finish(false) }) else {
            finish(false)
            return
        }

        proxy.updateConfiguration(data) { finish($0) }
    }
}
