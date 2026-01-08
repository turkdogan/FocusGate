//
//  DecisionLogger.swift
//  PageBlocker
//
//  Logs filtering decisions to App Group for display in main app
//

import Foundation

class DecisionLogger {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxEntries = 1000

    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted]
        self.decoder = JSONDecoder()

        // Get App Group container URL
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ConfigurationStore.appGroupIdentifier
        ) {
            self.fileURL = containerURL.appendingPathComponent("decision_log.json")
        } else {
            // Fallback to temporary directory
            let tempDir = FileManager.default.temporaryDirectory
            self.fileURL = tempDir.appendingPathComponent("pageblocker-log.json")
        }
    }

    // MARK: - Logging

    func log(hostname: String, action: DecisionLogEntry.Action, ruleSetName: String? = nil, processName: String? = nil) {
        let entry = DecisionLogEntry(
            hostname: hostname,
            action: action,
            ruleSetName: ruleSetName,
            processName: processName
        )

        var log = loadLog()
        log.add(entry)
        saveLog(log)
    }

    // MARK: - Persistence

    private func loadLog() -> DecisionLog {
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? decoder.decode(DecisionLog.self, from: data) else {
            return DecisionLog(maxEntries: maxEntries)
        }
        return log
    }

    private func saveLog(_ log: DecisionLog) {
        do {
            let data = try encoder.encode(log)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to save decision log: \(error)")
        }
    }

    func getRecentEntries(limit: Int = 100) -> [DecisionLogEntry] {
        let log = loadLog()
        return Array(log.entries.prefix(limit))
    }

    func clear() {
        let emptyLog = DecisionLog(maxEntries: maxEntries)
        saveLog(emptyLog)
    }
}
