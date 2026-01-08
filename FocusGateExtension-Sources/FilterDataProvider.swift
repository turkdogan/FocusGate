//
//  FilterDataProvider.swift
//  PageBlockerExtension
//
//  Network Extension filter provider - evaluates and blocks network flows
//

import Foundation
import NetworkExtension
import Network

class FilterDataProvider: NEFilterDataProvider {

    private var configuration: FilterConfiguration?
    private let configURL: URL
    private let logger: DecisionLogger

    override init() {
        // Get App Group container URL
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ConfigurationStore.appGroupIdentifier
        ) {
            self.configURL = containerURL.appendingPathComponent("config.json")
        } else {
            // Fallback
            let tempDir = FileManager.default.temporaryDirectory
            self.configURL = tempDir.appendingPathComponent("pageblocker-config.json")
        }

        self.logger = DecisionLogger()

        super.init()

        print("🚀 FilterDataProvider initialized")
        loadConfiguration()
    }

    // MARK: - Flow Handling

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        print("🟢 Filter starting...")
        loadConfiguration()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        print("🔴 Filter stopping with reason: \(reason)")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // Extract hostname from the flow
        guard let hostname = extractHostname(from: flow) else {
            // Cannot determine hostname, allow by default
            return .allow()
        }

        // Reload configuration (in production, consider caching with periodic reload)
        loadConfiguration()

        guard let config = configuration else {
            // No configuration, allow all
            return .allow()
        }

        // Evaluate against blocking rules
        let verdict = evaluateFlow(hostname: hostname, config: config)

        return verdict
    }

    // MARK: - Flow Evaluation

    private func evaluateFlow(hostname: String, config: FilterConfiguration) -> NEFilterNewFlowVerdict {
        let now = Date()
        let timezone = TimeZone.current

        // Check each blocked site
        for site in config.blockedSites where site.enabled {
            // Check if hostname matches pattern
            guard DomainMatcher.matches(hostname, pattern: site) else {
                continue
            }

            // If site has a rule set, check if it's currently active
            if let ruleSetId = site.ruleSetId {
                guard let ruleSet = config.ruleSets.first(where: { $0.id == ruleSetId }) else {
                    continue
                }

                if !ruleSet.isActive(at: now, in: timezone) {
                    // Rule set not active, don't block
                    continue
                }

                // Block and log
                logger.log(hostname: hostname, action: .block, ruleSetName: ruleSet.name)
                print("🚫 BLOCKED: \(hostname) (rule set: \(ruleSet.name))")
                return .drop()
            } else {
                // No rule set, always block
                logger.log(hostname: hostname, action: .block, ruleSetName: nil)
                print("🚫 BLOCKED: \(hostname) (always active)")
                return .drop()
            }
        }

        // No match, allow
        logger.log(hostname: hostname, action: .allow)
        print("✅ ALLOWED: \(hostname)")
        return .allow()
    }

    // MARK: - Hostname Extraction

    private func extractHostname(from flow: NEFilterFlow) -> String? {
        // Try to get hostname from socket flow
        if let socketFlow = flow as? NEFilterSocketFlow {
            if let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
                return remoteEndpoint.hostname
            }
        }

        // Try to get from browser flow (Safari, etc.)
        if let browserFlow = flow as? NEFilterBrowserFlow {
            if let url = browserFlow.request?.url,
               let host = url.host {
                return host
            }
        }

        return nil
    }

    // MARK: - Configuration Management

    private func loadConfiguration() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(FilterConfiguration.self, from: data) else {
            print("⚠️ Failed to load configuration from \(configURL.path)")
            return
        }

        self.configuration = config
        print("📥 Loaded configuration: \(config.blockedSites.count) sites, \(config.ruleSets.count) rule sets")
    }
}
