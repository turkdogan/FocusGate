//
//  ConfigurationStore.swift
//  FocusGate
//
//  Manages loading and saving filter configuration via App Group using UserDefaults
//

import Foundation
import Combine
import os.log

class ConfigurationStore: ObservableObject {
    @Published var configuration: FilterConfiguration {
        didSet {
            save()
        }
    }

    private let userDefaults: UserDefaults?
    private var pauseExpiryTimer: Timer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "ConfigurationStore")

    // App Group identifier - must match entitlements
    static let appGroupIdentifier = "group.dev.turkdogan.focusgate.shared"

    // Storage key
    private static let configurationKey = "filterConfiguration"

    // Posted after every save so FilterManager can push the new
    // configuration into the Network Extension preferences.
    static let configurationDidChange = Notification.Name("FocusGateConfigurationDidChange")

    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()

        // Get App Group UserDefaults
        self.userDefaults = UserDefaults(suiteName: ConfigurationStore.appGroupIdentifier)

        // Load existing configuration or create new
        if let data = userDefaults?.data(forKey: ConfigurationStore.configurationKey),
           let config = try? decoder.decode(FilterConfiguration.self, from: data) {
            self.configuration = config
            os_log("Loaded configuration from UserDefaults: %d sites, %d rule sets", log: logger, type: .info,
                   config.blockedSites.count, config.ruleSets.count)
        } else {
            self.configuration = FilterConfiguration()
            os_log("Created new configuration", log: logger, type: .info)
            // Save initial empty configuration
            save()
        }

        // A pause left over from a previous run: clear it if already
        // expired, or arm the expiry event if it is still ticking.
        schedulePauseExpiry()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try encoder.encode(configuration)
            userDefaults?.set(data, forKey: ConfigurationStore.configurationKey)
            userDefaults?.set(Date(), forKey: "lastUpdated")

            // Send Darwin notification to inform extension of changes
            notifyExtension()

            // The extension runs as root and cannot read this user's App Group
            // defaults, so the configuration must also travel through the NE
            // provider configuration. FilterManager listens for this.
            NotificationCenter.default.post(name: ConfigurationStore.configurationDidChange, object: nil)

            os_log("Saved configuration: %d sites, %d rule sets", log: logger, type: .info,
                   configuration.blockedSites.count, configuration.ruleSets.count)
        } catch {
            os_log("Failed to save configuration: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }

    private func notifyExtension() {
        // Post Darwin notification to inform extension of configuration changes
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("dev.turkdogan.focusgate.updated" as CFString),
            nil,
            nil,
            true
        )
        os_log("Sent Darwin notification to extension", log: logger, type: .debug)
    }

    func reload() {
        guard let data = userDefaults?.data(forKey: ConfigurationStore.configurationKey),
              let config = try? decoder.decode(FilterConfiguration.self, from: data) else {
            os_log("Failed to reload configuration", log: logger, type: .error)
            return
        }
        self.configuration = config
        os_log("Reloaded configuration: %d sites, %d rule sets", log: logger, type: .info,
               config.blockedSites.count, config.ruleSets.count)
    }

    // MARK: - Pause

    func pause(for duration: TimeInterval) {
        configuration.pausedUntil = Date().addingTimeInterval(duration)
        schedulePauseExpiry()
    }

    func resumeBlocking() {
        pauseExpiryTimer?.invalidate()
        pauseExpiryTimer = nil
        configuration.pausedUntil = nil
    }

    var isPaused: Bool { configuration.isPaused }

    /// The pause end is a wall-clock fact, but SwiftUI only redraws on
    /// published changes — without an event at expiry the menubar icon
    /// and status line stay frozen in their paused state. Clearing
    /// pausedUntil here also re-pushes the configuration, which flushes
    /// DNS records cached while the pause was open.
    private func schedulePauseExpiry() {
        pauseExpiryTimer?.invalidate()
        pauseExpiryTimer = nil

        guard let until = configuration.pausedUntil else { return }
        guard until > Date() else {
            configuration.pausedUntil = nil
            return
        }

        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            self?.pauseExpiryTimer = nil
            self?.configuration.pausedUntil = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseExpiryTimer = timer
    }

    // MARK: - Blocked Sites

    func addBlockedSite(_ site: BlockedSite) {
        configuration.blockedSites.append(site)
        save()
    }

    func removeBlockedSite(id: UUID) {
        configuration.blockedSites.removeAll { $0.id == id }
        save()
    }

    func updateBlockedSite(_ site: BlockedSite) {
        if let index = configuration.blockedSites.firstIndex(where: { $0.id == site.id }) {
            configuration.blockedSites[index] = site
            save()
        }
    }

    func toggleBlockedSite(id: UUID) {
        if let index = configuration.blockedSites.firstIndex(where: { $0.id == id }) {
            configuration.blockedSites[index].enabled.toggle()
            save()
        }
    }

    // MARK: - Rule Sets

    func addRuleSet(_ ruleSet: RuleSet) {
        configuration.ruleSets.append(ruleSet)
        save()
    }

    func removeRuleSet(id: UUID) {
        // Remove rule set
        configuration.ruleSets.removeAll { $0.id == id }

        // Clear rule set references from blocked sites
        for i in 0..<configuration.blockedSites.count {
            if configuration.blockedSites[i].ruleSetId == id {
                configuration.blockedSites[i].ruleSetId = nil
            }
        }

        save()
    }

    func updateRuleSet(_ ruleSet: RuleSet) {
        if let index = configuration.ruleSets.firstIndex(where: { $0.id == ruleSet.id }) {
            configuration.ruleSets[index] = ruleSet
            save()
        }
    }

    // MARK: - Helper Methods

    func getRuleSet(id: UUID) -> RuleSet? {
        return configuration.ruleSets.first { $0.id == id }
    }

    func getActiveRuleSets(at date: Date = Date(), in timezone: TimeZone = .current) -> [RuleSet] {
        return configuration.ruleSets.filter { $0.isActive(at: date, in: timezone) }
    }

    /// The currently-active schedule window with the latest end time, for
    /// "Work Hours until 17:00" style status lines.
    func currentActiveWindow(at date: Date = Date()) -> (name: String, until: TimeOfDay)? {
        let weekday = Calendar.current.component(.weekday, from: date)
        let now = TimeOfDay.now

        var best: (name: String, until: TimeOfDay)?
        for ruleSet in configuration.ruleSets {
            guard let day = ruleSet.schedules.first(where: { $0.weekday.rawValue == weekday }) else { continue }
            for window in day.windows where window.contains(time: now) {
                if best == nil || window.end > best!.until {
                    best = (ruleSet.name, window.end)
                }
            }
        }
        return best
    }
}
