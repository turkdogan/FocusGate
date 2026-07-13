//
//  BlockedSitesView.swift
//  PageBlocker
//
//  UI for managing blocked sites list
//

import SwiftUI

struct BlockedSitesView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @State private var newPattern: String = ""
    @State private var matchType: BlockedSite.MatchType = .domainAndSubdomains
    @State private var selectedRuleSetId: UUID? = nil
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var selectedSites: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Blocked Sites")
                .font(.title2)
                .bold()

            // Add new site
            GroupBox(label: Text("Add website or domain")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("example.com or *.reddit.com", text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addSite()
                            }

                        Button("Add") {
                            addSite()
                        }
                        .disabled(newPattern.isEmpty)
                        .keyboardShortcut(.return, modifiers: [])
                    }

                    Picker("Match type:", selection: $matchType) {
                        ForEach(BlockedSite.MatchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Picker("Rule set:", selection: $selectedRuleSetId) {
                        Text("Always active (no schedule)").tag(nil as UUID?)
                        ForEach(configStore.configuration.ruleSets) { ruleSet in
                            Text(ruleSet.name).tag(ruleSet.id as UUID?)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // List of blocked sites
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(configStore.configuration.blockedSites.count) blocked sites")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !selectedSites.isEmpty {
                        Button("Delete Selected (\(selectedSites.count))") {
                            deleteSelectedSites()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if configStore.configuration.blockedSites.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No blocked sites")
                            .foregroundColor(.secondary)
                        Text("Add a website above to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else {
                    List(selection: $selectedSites) {
                        ForEach(configStore.configuration.blockedSites) { site in
                            BlockedSiteRow(site: site, configStore: configStore)
                                .tag(site.id)
                        }
                        .onDelete(perform: deleteSites)
                    }
                }
            }
        }
        .alert("Invalid Pattern", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func addSite() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return }

        // Validate pattern
        guard DomainMatcher.isValidPattern(trimmed) else {
            errorMessage = "Invalid domain pattern. Please enter a valid domain like 'example.com' or '*.reddit.com'"
            showingError = true
            return
        }

        let site = BlockedSite(
            pattern: trimmed,
            matchType: matchType,
            enabled: true,
            ruleSetId: selectedRuleSetId
        )

        configStore.addBlockedSite(site)
        newPattern = ""
    }

    private func deleteSites(at offsets: IndexSet) {
        for index in offsets {
            let site = configStore.configuration.blockedSites[index]
            guard !site.isLocked else { continue }
            configStore.removeBlockedSite(id: site.id)
        }
    }

    private func deleteSelectedSites() {
        let lockedIds = Set(configStore.configuration.blockedSites.filter(\.isLocked).map(\.id))
        for id in selectedSites where !lockedIds.contains(id) {
            configStore.removeBlockedSite(id: id)
        }
        selectedSites.removeAll()
    }
}

// MARK: - Blocked Site Row

struct BlockedSiteRow: View {
    let site: BlockedSite
    let configStore: ConfigurationStore
    @State private var confirmingUnlock = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(site.isLocked)
                .help(site.isLocked ? "Locked — unlock to change" : (site.enabled ? "Blocking on" : "Blocking off"))

            Text(site.pattern)
                .font(.body)

            Spacer()

            // Inline editors — changes apply and reach the filter immediately
            Picker("", selection: matchTypeBinding) {
                ForEach(BlockedSite.MatchType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(site.isLocked)
            .help("How this pattern matches")

            Picker("", selection: ruleSetBinding) {
                Text("Always").tag(nil as UUID?)
                ForEach(configStore.configuration.ruleSets) { ruleSet in
                    Text(ruleSet.name).tag(ruleSet.id as UUID?)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(site.isLocked)
            .help("When this site is blocked")

            Button {
                if site.isLocked {
                    confirmingUnlock = true
                } else {
                    setLocked(true)
                }
            } label: {
                Image(systemName: site.isLocked ? "lock.fill" : "lock.open")
                    .foregroundColor(site.isLocked ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help(site.isLocked
                  ? "Locked: stays blocked during pauses and cannot be edited or deleted"
                  : "Lock this site: it will stay blocked even when the filter is paused")
            .confirmationDialog("Unlock \(site.pattern)?",
                                isPresented: $confirmingUnlock) {
                Button("Unlock", role: .destructive) {
                    setLocked(false)
                }
                Button("Keep Locked", role: .cancel) { }
            } message: {
                Text("Unlocked sites can be edited, paused, and deleted again.")
            }
        }
        .padding(.vertical, 4)
    }

    private func setLocked(_ locked: Bool) {
        var updated = site
        updated.locked = locked
        if locked {
            updated.enabled = true // locking implies blocking
        }
        configStore.updateBlockedSite(updated)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { site.enabled },
            set: { _ in configStore.toggleBlockedSite(id: site.id) }
        )
    }

    private var matchTypeBinding: Binding<BlockedSite.MatchType> {
        Binding(
            get: { site.matchType },
            set: { newValue in
                var updated = site
                updated.matchType = newValue
                configStore.updateBlockedSite(updated)
            }
        )
    }

    private var ruleSetBinding: Binding<UUID?> {
        Binding(
            get: { site.ruleSetId },
            set: { newValue in
                var updated = site
                updated.ruleSetId = newValue
                configStore.updateBlockedSite(updated)
            }
        )
    }
}

#Preview {
    BlockedSitesView()
        .environmentObject(ConfigurationStore())
        .frame(width: 700, height: 500)
}
