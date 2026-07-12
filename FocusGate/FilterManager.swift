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
    private let systemExtension = SystemExtensionManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        systemExtension.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.reflectExtensionState(state)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ConfigurationStore.configurationDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.pushConfigurationUpdate() }
            }
            .store(in: &cancellables)

        Task {
            await loadStatus()
        }
    }

    // MARK: - Vendor Configuration

    /// The extension runs as root and cannot see this user's App Group
    /// UserDefaults, so the blocklist is delivered inside the provider
    /// configuration instead.
    private func currentConfigData() -> Data? {
        UserDefaults(suiteName: ConfigurationStore.appGroupIdentifier)?
            .data(forKey: "filterConfiguration")
    }

    /// Re-embeds the latest blocklist into the enabled filter configuration.
    func pushConfigurationUpdate() async {
        do {
            try await manager.loadFromPreferences()
            guard manager.isEnabled, let providerConfig = manager.providerConfiguration else { return }
            guard let data = currentConfigData() else { return }

            providerConfig.vendorConfiguration = ["filterConfiguration": data]
            try await manager.saveToPreferences()
            print("✅ Pushed updated configuration to extension (\(data.count) bytes)")
        } catch {
            print("❌ Failed to push configuration update: \(error)")
        }
    }

    private func reflectExtensionState(_ state: SystemExtensionManager.ActivationState) {
        switch state {
        case .requesting:
            status = "Installing system extension..."
        case .needsUserApproval:
            status = "Approve the extension: System Settings > General > Login Items & Extensions"
        case .needsReboot:
            status = "Restart your Mac to finish installing the extension"
        case .failed(let message):
            status = "Extension error: \(message)"
        case .idle, .activated:
            break
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

        // The system extension must be activated before the filter configuration
        // can start it. This suspends until macOS reports it installed, which
        // includes waiting for user approval in System Settings on first run.
        try await systemExtension.activate()

        // Load current configuration to ensure we have the latest settings
        try await manager.loadFromPreferences()

        // Create filter configuration if it doesn't exist
        if manager.providerConfiguration == nil {
            print("📝 Creating new Network Extension configuration")

            let config = NEFilterProviderConfiguration()
            config.filterBrowsers = true
            config.filterSockets = true
            config.filterPackets = false

            // CRITICAL: Tell the system which extension to load
            config.filterDataProviderBundleIdentifier = "dev.turkdogan.FocusGate.FocusGateExtension"

            manager.providerConfiguration = config
            print("✅ Created configuration with bundle ID: dev.turkdogan.FocusGate.FocusGateExtension")
        } else {
            print("ℹ️ Using existing Network Extension configuration")
        }

        // Embed the current blocklist so the root-owned extension receives it
        if let data = currentConfigData() {
            manager.providerConfiguration?.vendorConfiguration = ["filterConfiguration": data]
        }

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
                print("📍 Go to: System Settings > Privacy & Security > Network Extensions")
                status = "Pending approval in System Settings > Privacy & Security > Network Extensions"
            }
        } catch {
            print("❌ Failed to enable filter: \(error)")
            status = "Error: \(error.localizedDescription)"
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

    // MARK: - Configuration Reset

    func resetConfiguration() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load current preferences
            try await manager.loadFromPreferences()

            // Remove the configuration completely
            print("🗑️ Removing old configuration...")
            try await manager.removeFromPreferences()
            print("✅ Old configuration removed")

            // Wait a moment
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Now enable with fresh configuration
            try await enable()
        } catch {
            print("❌ Failed to reset configuration: \(error)")
            throw error
        }
    }

    // MARK: - System Extension Management

    func openSystemSettings() {
        // Extension approval lives in General > Login Items & Extensions
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
