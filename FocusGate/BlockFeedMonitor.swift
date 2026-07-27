//
//  BlockFeedMonitor.swift
//  FocusGate
//
//  Keeps the activity feed for the whole app (menubar, Status tab,
//  notifications). Event-driven: the extension rings a Darwin
//  notification doorbell when new decisions land and only then do we
//  fetch — incrementally, entries newer than the last one we have.
//  A slow heartbeat keeps the feed-health indicator honest when no
//  blocks happen for a while.
//

import Combine
import Foundation
import UserNotifications
import os.log

@MainActor
final class BlockFeedMonitor: ObservableObject {
    /// Every decision we know about, newest first (capped).
    @Published private(set) var allDecisions: [DecisionLogEntry] = []

    /// Blocked hostnames deduplicated for the menubar, newest first.
    @Published private(set) var recentBlocks: [DecisionLogEntry] = []

    /// Whether the last fetch reached the extension —
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
    private var heartbeat: Timer?
    private let maxEntries = 500
    /// Newest timestamp already fetched; the incremental fetch cursor.
    private var fetchCursor = Date.distantPast
    /// Blocks older than this predate app launch — never notify about them.
    private var lastSeen = Date()
    /// Per-hostname cooldown so one page load (dozens of flows) is one notification.
    private var lastNotified: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60

    func start() {
        guard heartbeat == nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            os_log("Notification permission granted: %d", type: .info, granted ? 1 : 0)
        }

        registerDoorbell()

        // Health check only — real updates arrive via the doorbell.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(FocusGateXPC.decisionsDidChange as CFString),
            nil
        )
    }

    /// Manual refresh (Status tab button).
    func refresh() {
        poll()
    }

    /// Drops local state and refetches everything, e.g. after Clear Log.
    func reload() {
        fetchCursor = .distantPast
        allDecisions = []
        recentBlocks = []
        poll()
    }

    // MARK: - Doorbell

    private func registerDoorbell() {
        // C callback: no captures allowed, so recover self from the observer pointer.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<BlockFeedMonitor>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in monitor.poll() }
            },
            FocusGateXPC.decisionsDidChange as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Fetch

    private func poll() {
        ProviderXPCClient.shared.fetchRecentDecisions(since: fetchCursor) { [weak self] entries, reachable in
            guard let self else { return }

            // Publish only on change: quiet heartbeats must not wake SwiftUI.
            if self.feedHealthy != reachable {
                self.feedHealthy = reachable
            }
            guard !entries.isEmpty else { return }

            // Entries arrive newest first and are all newer than the cursor.
            let known = Set(self.allDecisions.map(\.id))
            let fresh = entries.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }

            self.fetchCursor = max(self.fetchCursor, fresh.map(\.timestamp).max() ?? self.fetchCursor)
            self.allDecisions = Array((fresh + self.allDecisions).prefix(self.maxEntries))

            var seenHosts = Set<String>()
            let blocks = self.allDecisions.filter { $0.action == .block }
            let dedupedBlocks = Array(blocks.filter { seenHosts.insert($0.hostname).inserted }.prefix(20))
            if dedupedBlocks.map(\.id) != self.recentBlocks.map(\.id) {
                self.recentBlocks = dedupedBlocks
            }

            let freshBlocks = fresh.filter { $0.action == .block && $0.timestamp > self.lastSeen }
            if let newest = freshBlocks.map(\.timestamp).max() {
                self.lastSeen = newest
            }
            self.notify(about: freshBlocks)
        }
    }

    // MARK: - Notifications

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
