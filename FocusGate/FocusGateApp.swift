//
//  FocusGateApp.swift
//  FocusGate
//
//  Main application entry point
//

import Combine
import SwiftUI

enum AppTab: Int, CaseIterable {
    case blockedSites, ruleSets, status

    var title: String {
        switch self {
        case .blockedSites: return "Blocked Sites"
        case .ruleSets: return "Rule Sets"
        case .status: return "Status"
        }
    }
}

final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .blockedSites
}

@main
struct FocusGateApp: App {
    @StateObject private var configStore = ConfigurationStore()
    @StateObject private var filterManager = FilterManager()
    @StateObject private var blockFeed = BlockFeedMonitor()
    @StateObject private var tabRouter = TabRouter()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(configStore)
                .environmentObject(filterManager)
                .environmentObject(blockFeed)
                .environmentObject(tabRouter)
                .frame(minWidth: 700, minHeight: 550)
                .onAppear { blockFeed.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(before: .toolbar) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button(tab.title) {
                        tabRouter.selection = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                }
                Divider()
            }
            CommandGroup(replacing: .appInfo) {
                Button("About FocusGate") {
                    NSApp.activate(ignoringOtherApps: true)
                    var options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .credits: NSAttributedString(
                            string: "System-wide website blocker.\nFree & open source — github.com/turkdogan/FocusGate",
                            attributes: [.font: NSFont.systemFont(ofSize: 11),
                                         .foregroundColor: NSColor.secondaryLabelColor]
                        ),
                    ]
                    // Load the icon straight from the bundle — the system icon
                    // cache can serve a stale generic icon until next reboot.
                    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        options[.applicationIcon] = icon
                    }
                    NSApp.orderFrontStandardAboutPanel(options: options)
                }
            }
            CommandGroup(replacing: .help) {
                Button("FocusGate Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
                Divider()
                Link("README on GitHub", destination: URL(string: "https://github.com/turkdogan/FocusGate#readme")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/turkdogan/FocusGate/issues")!)
            }
        }

        Window("FocusGate Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(configStore)
                .environmentObject(filterManager)
                .environmentObject(blockFeed)
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }

    private var menuBarSymbol: String {
        if !filterManager.isEnabled { return "shield.slash" }
        return configStore.isPaused ? "shield" : "shield.fill"
    }
}

struct MenuBarView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @EnvironmentObject var filterManager: FilterManager
    @EnvironmentObject var blockFeed: BlockFeedMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(statusLine)

            Divider()

            if filterManager.isEnabled {
                if configStore.isPaused {
                    Button("Resume Blocking Now") {
                        configStore.resumeBlocking()
                    }
                } else {
                    Button("Pause for 15 Minutes") {
                        configStore.pause(for: 15 * 60)
                    }
                    Button("Pause for 1 Hour") {
                        configStore.pause(for: 60 * 60)
                    }
                }
            } else {
                Button("Enable Filter") {
                    Task { try? await filterManager.enable() }
                }
            }

            Divider()

            if !blockFeed.recentBlocks.isEmpty {
                Text("Recently blocked")
                ForEach(blockFeed.recentBlocks.prefix(5)) { entry in
                    Text("⛔ \(entry.hostname)")
                }
                Divider()
            }

            Button("Open FocusGate") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private var statusLine: String {
        if !filterManager.isEnabled { return "Filter is off" }
        if let until = configStore.configuration.pausedUntil, configStore.isPaused {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let lockedCount = configStore.configuration.blockedSites.filter(\.isLocked).count
            let suffix = lockedCount > 0 ? " · \(lockedCount) locked site\(lockedCount == 1 ? "" : "s") still blocked" : ""
            return "Paused until \(formatter.string(from: until))\(suffix)"
        }
        let count = configStore.configuration.blockedSites.filter { $0.enabled }.count
        if let window = configStore.currentActiveWindow() {
            return "Blocking \(count) site\(count == 1 ? "" : "s") · \(window.name) until \(window.until.displayString)"
        }
        return "Blocking \(count) site\(count == 1 ? "" : "s")"
    }
}

struct ContentView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @EnvironmentObject var filterManager: FilterManager
    @EnvironmentObject var tabRouter: TabRouter

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            BlockedSitesView()
                .tabItem {
                    Label("Blocked Sites", systemImage: "xmark.shield")
                }
                .tag(AppTab.blockedSites)

            RuleSetsView()
                .tabItem {
                    Label("Rule Sets", systemImage: "calendar.badge.clock")
                }
                .tag(AppTab.ruleSets)

            StatusView()
                .tabItem {
                    Label("Status", systemImage: "chart.bar")
                }
                .tag(AppTab.status)
        }
        .padding()
    }
}


// MARK: - Settings

struct SettingsView: View {
    @AppStorage("notificationMode") private var notificationMode = BlockFeedMonitor.NotificationMode.all.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications")
                    .font(.headline)

                Picker("", selection: $notificationMode) {
                    ForEach(BlockFeedMonitor.NotificationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text("\"Once per site\" notifies the first time a site is blocked and stays quiet afterwards.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 6) {
                Text("FocusGate is free and open source.")
                    .foregroundColor(.secondary)
                Link("Star it on GitHub", destination: URL(string: "https://github.com/turkdogan/FocusGate")!)
                Spacer()
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}


// MARK: - Help

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How FocusGate works", systemImage: "shield.lefthalf.filled")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                HelpRow(number: "1", title: "Add sites",
                        text: "In Blocked Sites, type a domain and press Add. \"reddit.com\" with \"Domain + Subdomains\" also covers www, old, gql — everything under it.")
                HelpRow(number: "2", title: "Blocking is system-wide and instant",
                        text: "A system extension filters every connection on this Mac — all browsers, incognito included. Blocked sites fail immediately with \"server not found\".")
                HelpRow(number: "3", title: "Schedules",
                        text: "Create rule sets (like Work Hours) in the Rule Sets tab and assign sites to them from each site's menu. Overnight windows such as 22:00–06:00 cover that day's late evening and that day's early morning.")
                HelpRow(number: "4", title: "Pause and locks",
                        text: "The menubar shield pauses everything for 15 or 60 minutes — except locked sites, which hold through pauses and need a confirmation to unlock.")
                HelpRow(number: "5", title: "Good to know",
                        text: "Pages already open may keep working for a few minutes (browser cache and open connections). New connections are always enforced. System Settings can disable the extension — FocusGate adds friction, not handcuffs.")
            }

            Divider()

            HStack {
                Link("README", destination: URL(string: "https://github.com/turkdogan/FocusGate#readme")!)
                Link("Report an issue", destination: URL(string: "https://github.com/turkdogan/FocusGate/issues")!)
                Spacer()
                Text("Free & open source · MIT")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct HelpRow: View {
    let number: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundColor(.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
