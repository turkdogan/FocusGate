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
    @Published var dnsProxyEnabled: Bool = false

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
        guard let data = currentConfigData() else { return }

        // Persist first: if the live push fails and we must restart the
        // session, the restarted provider reads this saved copy.
        do {
            try await manager.loadFromPreferences()
            guard manager.isEnabled, let providerConfig = manager.providerConfiguration else { return }

            providerConfig.vendorConfiguration = ["filterConfiguration": data]
            try await manager.saveToPreferences()
        } catch {
            print("❌ Failed to persist configuration update: \(error)")
        }

        // Live update: the running provider applies this immediately.
        let delivered = await withCheckedContinuation { continuation in
            ProviderXPCClient.shared.updateConfiguration(data) { ok in
                continuation.resume(returning: ok)
            }
        }

        if delivered {
            print("✅ Pushed updated configuration to extension (\(data.count) bytes)")
        } else {
            // Known macOS issue: the extension's XPC registration can go
            // stale after a system extension upgrade. Restarting the
            // filter session re-reads the saved config and re-registers.
            print("⚠️ Live push failed — repairing filter session")
            await repairFilterSession()
        }
    }

    private var isRepairing = false

    /// Bounces the filter and DNS proxy sessions so the extension process
    /// restarts, re-reads the persisted configuration, and re-registers
    /// its XPC service. Used when a live push cannot reach the extension.
    private func repairFilterSession() async {
        guard !isRepairing else { return }
        isRepairing = true
        defer { isRepairing = false }

        status = "Re-syncing filter..."

        do {
            try await manager.loadFromPreferences()
            guard manager.isEnabled else { return }

            let dnsManager = NEDNSProxyManager.shared()
            try await dnsManager.loadFromPreferences()
            let dnsWasEnabled = dnsManager.isEnabled

            manager.isEnabled = false
            try await manager.saveToPreferences()
            if dnsWasEnabled {
                dnsManager.isEnabled = false
                try await dnsManager.saveToPreferences()
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)

            try await manager.loadFromPreferences()
            manager.isEnabled = true
            try await manager.saveToPreferences()
            if dnsWasEnabled {
                try await dnsManager.loadFromPreferences()
                dnsManager.isEnabled = true
                try await dnsManager.saveToPreferences()
            }

            print("🔧 Filter session repaired")
            await loadStatus()
        } catch {
            print("❌ Filter repair failed: \(error)")
            status = "Filter out of sync — use Disable then Enable Filter"
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
        case .activated:
            status = isEnabled ? "Active" : "Inactive"
        case .idle:
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

            // If the filter is already set up, re-request activation so a
            // newer bundled extension version is staged automatically
            // (no-op when the installed version is current).
            if manager.providerConfiguration != nil {
                try? await systemExtension.activate()
            }

            // Users who enabled the filter before the DNS proxy existed
            // get it switched on here.
            if manager.isEnabled {
                try? await enableDNSProxy()
                let dnsManager = NEDNSProxyManager.shared()
                try? await dnsManager.loadFromPreferences()
                dnsProxyEnabled = dnsManager.isEnabled

                // Sync check: pushes the current config and self-repairs
                // if the extension's XPC channel went stale (which can
                // happen after extension upgrades).
                await pushConfigurationUpdate()
            }
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
            try await enableDNSProxy()
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
            try? await disableDNSProxy()
            print("✅ Filter disabled successfully")
            await loadStatus()
        } catch {
            print("❌ Failed to disable filter: \(error)")
            throw error
        }
    }

    // MARK: - DNS Proxy

    /// The DNS proxy makes blocked domains fail instantly (NXDOMAIN)
    /// instead of timing out. It rides the same system extension.
    private func enableDNSProxy() async throws {
        let dnsManager = NEDNSProxyManager.shared()
        try await dnsManager.loadFromPreferences()

        let bundleID = "dev.turkdogan.FocusGate.FocusGateExtension"
        if dnsManager.isEnabled,
           dnsManager.providerProtocol?.providerBundleIdentifier == bundleID {
            return // already configured
        }

        let proto = NEDNSProxyProviderProtocol()
        proto.providerBundleIdentifier = bundleID
        dnsManager.providerProtocol = proto
        dnsManager.localizedDescription = "FocusGate Instant Block"
        dnsManager.isEnabled = true

        try await dnsManager.saveToPreferences()
        print("✅ DNS proxy enabled")
    }

    private func disableDNSProxy() async throws {
        let dnsManager = NEDNSProxyManager.shared()
        try await dnsManager.loadFromPreferences()
        dnsManager.isEnabled = false
        try await dnsManager.saveToPreferences()
        print("✅ DNS proxy disabled")
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
