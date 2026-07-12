//
//  FilterDataProvider.swift
//  FocusGateExtension
//
//  Network Extension filter provider - evaluates and blocks network flows
//

import Foundation
import NetworkExtension
import Network
import os.log

/// Shared storage mechanism for communicating between main app and extension
class SharedBlocklist {
    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "SharedBlocklist")
    private let userDefaults = UserDefaults(suiteName: ConfigurationStore.appGroupIdentifier)

    // MARK: - Storage Keys
    private enum StorageKeys {
        static let configuration = "filterConfiguration"
        static let lastUpdated = "lastUpdated"
    }

    init() {}

    // MARK: - Public Properties

    var configuration: FilterConfiguration? {
        get {
            os_log("📥 Attempting to load configuration from UserDefaults...", log: logger, type: .debug)

            guard let userDefaults = userDefaults else {
                os_log("❌ ERROR: UserDefaults is nil! App Group not accessible.", log: logger, type: .error)
                return nil
            }

            guard let data = userDefaults.data(forKey: StorageKeys.configuration) else {
                os_log("❌ ERROR: No data found for key '%{public}@' in UserDefaults", log: logger, type: .error,
                       StorageKeys.configuration)
                return nil
            }

            os_log("📦 Found data in UserDefaults, size: %d bytes", log: logger, type: .debug, data.count)

            guard let config = try? JSONDecoder().decode(FilterConfiguration.self, from: data) else {
                os_log("❌ ERROR: Failed to decode FilterConfiguration from data", log: logger, type: .error)
                return nil
            }

            os_log("✅ Successfully decoded configuration", log: logger, type: .debug)
            return config
        }
        set {
            guard let newValue = newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                os_log("Failed to encode configuration", log: logger, type: .error)
                return
            }
            userDefaults?.set(data, forKey: StorageKeys.configuration)
            userDefaults?.set(Date(), forKey: StorageKeys.lastUpdated)
            os_log("Updated configuration: %d sites, %d rule sets", log: logger, type: .info,
                   newValue.blockedSites.count, newValue.ruleSets.count)
        }
    }

    // MARK: - Public Methods

    func loadConfiguration() {
        let config = configuration
        os_log("Loaded configuration: %d sites, %d rule sets", log: logger, type: .info,
               config?.blockedSites.count ?? 0, config?.ruleSets.count ?? 0)
    }
}

class FilterDataProvider: NEFilterDataProvider {

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "FilterDataProvider")
    private var sharedStorage: SharedBlocklist
    private let decisionLogger: DecisionLogger
    private let fileLogger = FileLogger()

    /// Active configuration, cached so flows don't re-decode JSON.
    /// Sourced from the provider configuration's vendorConfiguration — the
    /// extension runs as root and cannot read the user's App Group defaults.
    private var activeConfig: FilterConfiguration?

    private func loadConfigurationFromProvider() -> FilterConfiguration? {
        guard let vendor = filterConfiguration.vendorConfiguration,
              let data = vendor["filterConfiguration"] as? Data else {
            os_log("No vendorConfiguration present in filter configuration", log: logger, type: .error)
            return nil
        }
        guard let config = try? JSONDecoder().decode(FilterConfiguration.self, from: data) else {
            os_log("Failed to decode vendorConfiguration data (%d bytes)", log: logger, type: .error, data.count)
            return nil
        }
        return config
    }

    override init() {
        self.sharedStorage = SharedBlocklist()
        self.decisionLogger = DecisionLogger()
        super.init()

        fileLogger.log("🚀 FilterDataProvider initialized")
        os_log("FilterDataProvider initialized", log: logger, type: .info)
    }

    // MARK: - Flow Handling

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        fileLogger.log("🚀 startFilter called")
        os_log("🚀 FilterDataProvider starting...", log: logger, type: .info)

        // Expose the activity feed to the main app and accept live
        // configuration pushes (the saved provider configuration is only
        // re-read on restart).
        ProviderXPCService.shared.configurationUpdateHandler = { [weak self] config in
            self?.activeConfig = config
        }
        ProviderXPCService.shared.start()

        // Primary source: vendorConfiguration embedded by the main app.
        // Fallback: shared storage (works only if extension and app run as
        // the same user, kept for compatibility).
        sharedStorage.loadConfiguration()
        activeConfig = loadConfigurationFromProvider() ?? sharedStorage.configuration

        // Log initial state
        if let config = activeConfig {
            fileLogger.log("✅ Config loaded: \(config.blockedSites.count) sites, \(config.ruleSets.count) rule sets")
            os_log("✅ Configuration loaded - Sites: %d, Rule sets: %d", log: logger, type: .info,
                   config.blockedSites.count, config.ruleSets.count)

            // Log the actual blocked sites
            for site in config.blockedSites {
                fileLogger.log("📝 Site: \(site.pattern) enabled=\(site.enabled)")
                os_log("📝 Blocked site: %{public}@ (enabled: %d)", log: logger, type: .info,
                       site.pattern, site.enabled ? 1 : 0)
            }
        } else {
            fileLogger.log("❌ ERROR: No configuration loaded!")
            os_log("❌ ERROR: No configuration loaded! Extension will allow all traffic.", log: logger, type: .error)
        }

        // Set up monitoring for configuration changes via Darwin notifications
        setupConfigurationChangeMonitoring()

        fileLogger.log("✅ Filter started successfully")
        os_log("✅ Content filter started successfully", log: logger, type: .info)
        completionHandler(nil)
    }

    private func setupConfigurationChangeMonitoring() {
        // Use Darwin notifications to listen for changes from main app
        let notificationName = "dev.turkdogan.focusgate.updated" as CFString
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())

        CFNotificationCenterAddObserver(
            center,
            observer,
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let provider = Unmanaged<FilterDataProvider>.fromOpaque(observer).takeUnretainedValue()
                provider.reloadConfiguration()
            },
            notificationName,
            nil,
            .deliverImmediately
        )

        os_log("Darwin notification observer registered for configuration changes", log: logger, type: .info)
    }

    private func reloadConfiguration() {
        os_log("Reloading configuration", log: logger, type: .info)

        sharedStorage.loadConfiguration()
        activeConfig = loadConfigurationFromProvider() ?? sharedStorage.configuration

        if let config = activeConfig {
            os_log("Configuration reloaded - Sites: %d, Rule sets: %d", log: logger, type: .info,
                   config.blockedSites.count, config.ruleSets.count)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("Stopping content filter, reason: %d", log: logger, type: .info, reason.rawValue)
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let hostname = extractHostname(from: flow) else {
            return .allow()
        }

        guard let config = activeConfig else {
            os_log("No configuration available, allowing %{public}@", log: logger, type: .debug, hostname)
            return .allow()
        }

        if config.isPaused {
            return .allow()
        }

        return evaluateFlow(hostname: hostname, config: config)
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
                ProviderXPCService.shared.decisions.add(hostname: hostname, action: .block, ruleSetName: ruleSet.name)
                os_log("BLOCKED: %{public}@ (rule set: %{public}@)", log: logger, type: .info, hostname, ruleSet.name)
                return .drop()
            } else {
                // No rule set, always block
                ProviderXPCService.shared.decisions.add(hostname: hostname, action: .block)
                os_log("BLOCKED: %{public}@ (always active)", log: logger, type: .info, hostname)
                return .drop()
            }
        }

        // No match, allow. Deliberately not recorded in the activity feed:
        // allows are every connection the Mac makes — noise that buries the
        // blocks and a privacy liability worth avoiding.
        os_log("ALLOWED: %{public}@", log: logger, type: .debug, hostname)
        return .allow()
    }

    // MARK: - Hostname Extraction

    private func extractHostname(from flow: NEFilterFlow) -> String? {
        // Get hostname from socket flow
        if let socketFlow = flow as? NEFilterSocketFlow {
            // Try remoteHostname first (preferred method)
            if let hostname = socketFlow.remoteHostname, !hostname.isEmpty {
                os_log("Extracted hostname: %{public}@", log: logger, type: .debug, hostname)
                return hostname
            }

            // Try URL if available
            if let url = socketFlow.url, let host = url.host, !host.isEmpty {
                os_log("Extracted hostname from URL: %{public}@", log: logger, type: .debug, host)
                return host
            }

            // Fallback to deprecated NWHostEndpoint
            if let hostEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
                let hostname = hostEndpoint.hostname
                os_log("Extracted hostname from NWHostEndpoint: %{public}@", log: logger, type: .debug, hostname)
                return hostname
            }
        }

        os_log("Could not extract hostname from flow", log: logger, type: .debug)
        return nil
    }

}
