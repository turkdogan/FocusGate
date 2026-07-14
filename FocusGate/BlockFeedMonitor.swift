//
//  BlockFeedMonitor.swift
//  FocusGate
//
//  Polls the extension's activity feed in the background, keeps the
//  latest blocks for the menubar, and posts a notification when a
//  site is blocked so the user gets immediate feedback instead of a
//  silently hanging page.
//

import Combine
import Foundation
import UserNotifications
import os.log

@MainActor
final class BlockFeedMonitor: ObservableObject {
    @Published private(set) var recentBlocks: [DecisionLogEntry] = []

    /// Whether the last activity-feed fetch reached the extension —
    /// the health indicator for the XPC channel.
    @Published private(set) var feedHealthy: Bool = false

    /// User-facing notification behavior, set from Settings.
    enum NotificationMode: String, CaseIterable {
        case off, firstPerSite, all

        var label: String {
            switch self {
            case .off: return "Off"
            case .firstPerSite: return "Once per site"
            case .all: return "Every block"
            }
        }
    }

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "BlockFeedMonitor")
    private var timer: Timer?
    private var lastSeen = Date()
    /// Per-hostname cooldown so one page load (dozens of flows) is one notification.
    private var lastNotified: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60

    func start() {
        guard timer == nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            os_log("Notification permission granted: %d", type: .info, granted ? 1 : 0)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        ProviderXPCClient.shared.fetchRecentDecisions { [weak self] entries, reachable in
            guard let self else { return }
            self.feedHealthy = reachable

            let blocks = entries.filter { $0.action == .block }

            // One page load fans out into dozens of flows to the same host;
            // show each hostname once (newest first).
            var seenHosts = Set<String>()
            self.recentBlocks = Array(blocks.filter { seenHosts.insert($0.hostname).inserted }.prefix(20))

            let fresh = blocks.filter { $0.timestamp > self.lastSeen }
            if let newest = blocks.first?.timestamp, newest > self.lastSeen {
                self.lastSeen = newest
            }
            self.notify(about: fresh)
        }
    }

    private func notify(about entries: [DecisionLogEntry]) {
        let mode = NotificationMode(rawValue: UserDefaults.standard.string(forKey: "notificationMode") ?? "") ?? .all
        guard mode != .off else { return }

        let now = Date()
        var toNotify: [DecisionLogEntry] = []
        for entry in entries {
            let host = entry.hostname
            if let last = lastNotified[host] {
                if mode == .firstPerSite { continue }                       // once per app session
                if now.timeIntervalSince(last) < notificationCooldown { continue }
            }
            if !toNotify.contains(where: { $0.hostname == host }) {
                toNotify.append(entry)
                lastNotified[host] = now
            }
        }

        for entry in toNotify {
            let content = UNMutableNotificationContent()
            content.title = "Blocked · \(entry.reasonLabel)"
            content.body = entry.hostname
            content.sound = nil

            let request = UNNotificationRequest(identifier: "block-\(entry.hostname)-\(now.timeIntervalSince1970)",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
