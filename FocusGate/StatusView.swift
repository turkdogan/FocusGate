//
//  StatusView.swift
//  PageBlocker
//
//  UI for filter status and activity log
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var filterManager: FilterManager
    @EnvironmentObject var configStore: ConfigurationStore
    @EnvironmentObject var blockFeed: BlockFeedMonitor
    @State private var logEntries: [DecisionLogEntry] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filter Status")
                .font(.title2)
                .bold()

            // Setup guidance only while setup is actually needed
            if !filterManager.isEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Click \"Enable Filter\" below, then approve the extension in System Settings when macOS asks (General > Login Items & Extensions > Network Extensions).")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button("Open System Settings") {
                            filterManager.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
            }

            // Filter status
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(filterManager.isEnabled ? Color.green : Color.red)
                            .frame(width: 12, height: 12)

                        Text(filterManager.status)
                            .font(.headline)

                        Spacer()

                        if filterManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            if filterManager.isEnabled {
                                Button("Disable Filter") {
                                    Task {
                                        try? await filterManager.disable()
                                    }
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Enable Filter") {
                                    Task {
                                        try? await filterManager.enable()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            // Repair action for broken installs, tucked away
                            Menu {
                                Button("Reset Filter Configuration") {
                                    Task {
                                        try? await filterManager.resetConfiguration()
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Advanced")
                        }
                    }

                    if !filterManager.isEnabled && filterManager.status.contains("approval") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Filter requires approval in System Settings")
                                .font(.caption)
                            Spacer()
                            Button("Open System Settings") {
                                filterManager.openSystemSettings()
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Health checklist: every layer at a glance
                    if filterManager.isEnabled {
                        Divider()
                        HStack(spacing: 18) {
                            HealthItem(label: "Filter", healthy: filterManager.isEnabled)
                            HealthItem(label: "Instant DNS", healthy: filterManager.dnsProxyEnabled)
                            HealthItem(label: "Live feed", healthy: blockFeed.feedHealthy,
                                       unhealthyHint: "Feed unavailable — blocking still works. A restart of your Mac restores it.")
                            Spacer()
                        }
                    }

                    // Active rule sets
                    let activeRuleSets = configStore.getActiveRuleSets()
                    if !activeRuleSets.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active rule sets:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(activeRuleSets) { ruleSet in
                                HStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(ruleSet.name)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    // Statistics
                    Divider()

                    HStack(spacing: 20) {
                        StatBox(
                            title: "Blocked Sites",
                            value: "\(configStore.configuration.blockedSites.filter { $0.enabled }.count)",
                            color: .red
                        )

                        StatBox(
                            title: "Rule Sets",
                            value: "\(configStore.configuration.ruleSets.count)",
                            color: .blue
                        )

                        StatBox(
                            title: "Recent Blocks",
                            value: "\(logEntries.filter { $0.action == .block }.count)",
                            color: .orange
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            // Activity log
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recently Blocked")
                        .font(.headline)

                    Spacer()

                    Button("Refresh") {
                        loadLog()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Clear Log") {
                        clearLog()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                if logEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No blocked attempts yet")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                } else {
                    List {
                        ForEach(logEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadLog()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Actions

    private func loadLog() {
        ProviderXPCClient.shared.fetchRecentDecisions { entries, _ in
            logEntries = Array(entries.prefix(100))
        }
    }

    private func clearLog() {
        ProviderXPCClient.shared.clearDecisions { _ in
            loadLog()
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadLog()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Health Item

struct HealthItem: View {
    let label: String
    let healthy: Bool
    var unhealthyHint: String = ""

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(healthy ? .green : .orange)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .help(healthy ? "\(label): OK" : (unhealthyHint.isEmpty ? "\(label): not running" : unhealthyHint))
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: DecisionLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Image(systemName: "xmark.shield.fill")
                .foregroundColor(.red)
                .font(.caption)

            Text(entry.hostname)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(entry.reasonLabel)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(entry.locked == true ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.15))
                .foregroundColor(entry.locked == true ? .orange : .primary)
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    StatusView()
        .environmentObject(FilterManager())
        .environmentObject(ConfigurationStore())
        .frame(width: 700, height: 500)
}
