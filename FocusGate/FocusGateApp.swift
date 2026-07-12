//
//  FocusGateApp.swift
//  FocusGate
//
//  Main application entry point
//

import SwiftUI

@main
struct FocusGateApp: App {
    @StateObject private var configStore = ConfigurationStore()
    @StateObject private var filterManager = FilterManager()
    @StateObject private var blockFeed = BlockFeedMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(configStore)
                .environmentObject(filterManager)
                .environmentObject(blockFeed)
                .frame(minWidth: 700, minHeight: 550)
                .onAppear { blockFeed.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
            return "Paused until \(formatter.string(from: until))"
        }
        let count = configStore.configuration.blockedSites.filter { $0.enabled }.count
        return "Blocking \(count) site\(count == 1 ? "" : "s")"
    }
}

struct ContentView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @EnvironmentObject var filterManager: FilterManager

    var body: some View {
        TabView {
            BlockedSitesView()
                .tabItem {
                    Label("Blocked Sites", systemImage: "xmark.shield")
                }

            RuleSetsView()
                .tabItem {
                    Label("Rule Sets", systemImage: "calendar.badge.clock")
                }

            StatusView()
                .tabItem {
                    Label("Status", systemImage: "chart.bar")
                }
        }
        .padding()
    }
}
