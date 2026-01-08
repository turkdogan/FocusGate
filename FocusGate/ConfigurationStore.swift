//
//  ConfigurationStore.swift
//  PageBlocker
//
//  Manages loading and saving filter configuration via App Group
//

import Foundation
import Combine

class ConfigurationStore: ObservableObject {
    @Published var configuration: FilterConfiguration

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // App Group identifier - must match entitlements
    static let appGroupIdentifier = "group.dev.turkdogan.focusgate.shared"

    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()

        // Get App Group container URL
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ConfigurationStore.appGroupIdentifier
        ) {
            self.fileURL = containerURL.appendingPathComponent("config.json")
        } else {
            // Fallback to temporary directory if App Group not available (for development)
            print("⚠️ Warning: App Group container not available, using temporary directory")
            let tempDir = FileManager.default.temporaryDirectory
            self.fileURL = tempDir.appendingPathComponent("pageblocker-config.json")
        }

        // Load existing configuration or create new
        if let data = try? Data(contentsOf: fileURL),
           let config = try? decoder.decode(FilterConfiguration.self, from: data) {
            self.configuration = config
            print("✅ Loaded configuration from \(fileURL.path)")
        } else {
            self.configuration = FilterConfiguration()
            print("📝 Created new configuration at \(fileURL.path)")
        }
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
            print("💾 Saved configuration to \(fileURL.path)")
        } catch {
            print("❌ Failed to save configuration: \(error)")
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? decoder.decode(FilterConfiguration.self, from: data) else {
            return
        }
        self.configuration = config
        print("🔄 Reloaded configuration from \(fileURL.path)")
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
}
