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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(configStore)
                .environmentObject(filterManager)
                .frame(minWidth: 700, minHeight: 550)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
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
