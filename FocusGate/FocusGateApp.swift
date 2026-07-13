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
            CommandMenu("View") {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button(tab.title) {
                        tabRouter.selection = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                }
            }
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
