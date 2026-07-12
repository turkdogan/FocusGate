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
    @State private var logEntries: [DecisionLogEntry] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filter Status")
                .font(.title2)
                .bold()

            GroupBox("Network Extension Setup") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("The FocusGate content filter extension ships with the app, so there is nothing extra to install. Click \"Enable Filter\" below and then approve the extension in System Settings > Privacy & Security > Network Extensions when prompted.")
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

                            // Reset configuration button
                            Button("Reset Configuration") {
                                Task {
                                    try? await filterManager.resetConfiguration()
                                }
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.orange)
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
                    Text("Recent Activity")
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
                        Text("No recent activity")
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
        ProviderXPCClient.shared.fetchRecentDecisions { entries in
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

            Text(entry.hostname)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let processName = entry.processName {
                Text(processName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
            }

            Text(entry.action.rawValue.uppercased())
                .font(.caption)
                .bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(entry.action == .block ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                .foregroundColor(entry.action == .block ? .red : .green)
                .cornerRadius(4)
                .frame(width: 70)
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
