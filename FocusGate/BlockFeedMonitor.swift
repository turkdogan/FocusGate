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
        ProviderXPCClient.shared.fetchRecentDecisions { [weak self] entries in
            guard let self else { return }

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
        let now = Date()
        // One notification per hostname per cooldown window
        var hosts: [String] = []
        for entry in entries {
            let host = entry.hostname
            if let last = lastNotified[host], now.timeIntervalSince(last) < notificationCooldown {
                continue
            }
            if !hosts.contains(host) {
                hosts.append(host)
                lastNotified[host] = now
            }
        }

        for host in hosts {
            let content = UNMutableNotificationContent()
            content.title = "Site blocked"
            content.body = host
            content.sound = nil

            let request = UNNotificationRequest(identifier: "block-\(host)-\(now.timeIntervalSince1970)",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
