//
//  FilterManager.swift
//  PageBlocker
//
//  Manages NetworkExtension filter activation and status
//

import Foundation
import NetworkExtension
import Combine
import AppKit

@MainActor
class FilterManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var status: String = "Unknown"
    @Published var isLoading: Bool = false

    private let manager = NEFilterManager.shared()

    init() {
        Task {
            await loadStatus()
        }
    }

    // MARK: - Status

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await manager.loadFromPreferences()
            self.isEnabled = manager.isEnabled
            self.status = manager.isEnabled ? "Active" : "Inactive"
            print("📊 Filter status: \(status)")
        } catch {
            self.status = "Error: \(error.localizedDescription)"
            print("❌ Failed to load filter status: \(error)")
        }
    }

    // MARK: - Activation

    func enable() async throws {
        isLoading = true
        defer { isLoading = false }

        // First, install the system extension if not already installed
        let extensionInstalled = await withCheckedContinuation { continuation in
            SystemExtensionManager.shared.installExtension { success, error in
                if let error = error {
                    print("⚠️ Extension installation error: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }

        if !extensionInstalled {
            print("⚠️ System extension installation pending or failed")
            status = "System extension requires approval in System Settings > General > Login Items & Extensions"
            return
        }

        // Wait a moment for the extension to be ready
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Create filter configuration
        let config = NEFilterProviderConfiguration()
        config.filterBrowsers = true
        config.filterSockets = true

        manager.providerConfiguration = config
        manager.isEnabled = true
        manager.localizedDescription = "FocusGate Content Filter"

        do {
            try await manager.saveToPreferences()
            print("✅ Filter enabled successfully")

            // Reload to confirm
            await loadStatus()

            // Note: User must approve in System Settings for filter to actually start
            if !isEnabled {
                print("⚠️ Filter requires user approval in System Settings")
                status = "Pending approval in System Settings"
            }
        } catch {
            print("❌ Failed to enable filter: \(error)")
            throw error
        }
    }

    func disable() async throws {
        isLoading = true
        defer { isLoading = false }

        manager.isEnabled = false

        do {
            try await manager.saveToPreferences()
            print("✅ Filter disabled successfully")
            await loadStatus()
        } catch {
            print("❌ Failed to disable filter: \(error)")
            throw error
        }
    }

    // MARK: - System Extension Management

    func openSystemSettings() {
        // Open System Settings to Network Extensions
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_NetworkExtensions") {
            NSWorkspace.shared.open(url)
        }
    }
}
