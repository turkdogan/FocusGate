//
//  ProviderXPCService.swift
//  FocusGateExtension
//
//  Hosts the mach service the main app connects to for the activity feed.
//

import Foundation
import os.log

/// Thread-safe in-memory store of recent filtering decisions.
/// Replaces per-flow JSON file writes, which are both too slow for the
/// flow path and invisible to the app (root vs user container).
final class DecisionStore {
    private let queue = DispatchQueue(label: "dev.turkdogan.FocusGate.decisions")
    private var entries: [DecisionLogEntry] = []
    private let maxEntries = 500

    func add(hostname: String, action: DecisionLogEntry.Action, ruleSetName: String? = nil, processName: String? = nil) {
        let entry = DecisionLogEntry(hostname: hostname, action: action,
                                     ruleSetName: ruleSetName, processName: processName)
        queue.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries.removeLast(self.entries.count - self.maxEntries)
            }
        }
    }

    func recent(since: Date) -> [DecisionLogEntry] {
        queue.sync { entries.filter { $0.timestamp > since } }
    }

    func clear() {
        queue.async { self.entries.removeAll() }
    }
}

final class ProviderXPCService: NSObject {
    static let shared = ProviderXPCService()

    let decisions = DecisionStore()

    /// Set by the provider; called with each configuration pushed by the app.
    var configurationUpdateHandler: ((FilterConfiguration) -> Void)?

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "ProviderXPCService")
    private var listener: NSXPCListener?

    func start() {
        guard listener == nil else { return }

        let newListener = NSXPCListener(machServiceName: FocusGateXPC.serviceName)
        newListener.delegate = self
        newListener.resume()
        listener = newListener

        os_log("XPC listener started on %{public}@", log: logger, type: .info, FocusGateXPC.serviceName)
    }
}

// MARK: - NSXPCListenerDelegate

extension ProviderXPCService: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Enforced by XPC on every message from this connection; clients
        // not signed by our team get their messages dropped.
        newConnection.setCodeSigningRequirement(FocusGateXPC.codeSigningRequirement)

        newConnection.exportedInterface = NSXPCInterface(with: ProviderCommunication.self)
        newConnection.exportedObject = self
        newConnection.resume()

        os_log("Accepted XPC connection from pid %d", log: logger, type: .info, newConnection.processIdentifier)
        return true
    }
}

// MARK: - ProviderCommunication

extension ProviderXPCService: ProviderCommunication {
    func fetchRecentDecisions(sinceTimestamp: Double, reply: @escaping (Data) -> Void) {
        let since = Date(timeIntervalSince1970: sinceTimestamp)
        let entries = decisions.recent(since: since)
        reply((try? JSONEncoder().encode(entries)) ?? Data())
    }

    func clearDecisions(reply: @escaping (Bool) -> Void) {
        decisions.clear()
        reply(true)
    }

    func updateConfiguration(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let config = try? JSONDecoder().decode(FilterConfiguration.self, from: data) else {
            os_log("Rejected configuration update: undecodable payload (%d bytes)",
                   log: logger, type: .error, data.count)
            reply(false)
            return
        }

        os_log("Configuration updated over XPC - Sites: %d, paused: %d",
               log: logger, type: .info, config.blockedSites.count, config.isPaused ? 1 : 0)
        configurationUpdateHandler?(config)
        reply(true)
    }
}
