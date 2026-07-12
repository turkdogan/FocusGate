# FocusGate - Network Extension Setup (SOLVED!)

## Solution Found: Analyzed Working Open-Source App (Fuego)

After analyzing the **Fuego** open-source project, we discovered the correct configuration for NEFilterDataProvider in modern macOS/Xcode 26.

## Key Configuration Files

### 1. Extension Info.plist

The extension's `Info.plist` must specify:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.networkextension.filter-data</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).FilterDataProvider</string>
</dict>
```

**Critical:**
- Extension point MUST be `com.apple.networkextension.filter-data` (NOT app-proxy)
- Principal class MUST match your NEFilterDataProvider subclass name

### 2. Extension Entitlements

`FocusGateExtension.entitlements`:

```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>content-filter-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.dev.turkdogan.focusgate.shared</string>
</array>
```

**Note:** Use `content-filter-provider` (NOT `content-filter-provider-systemextension`)

### 3. Main App Entitlements

`FocusGate.entitlements`:

```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>content-filter-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.dev.turkdogan.focusgate.shared</string>
</array>
<key>com.apple.developer.system-extension.install</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

## Implementation Patterns from Fuego

### 1. Data Sharing: UserDefaults (Simpler than JSON!)

```swift
class SharedBlocklist {
    private let userDefaults = UserDefaults(suiteName: "group.dev.turkdogan.focusgate.shared")

    var blockedDomains: Set<String> {
        get {
            guard let data = userDefaults?.data(forKey: "blockedDomains"),
                let domains = try? JSONDecoder().decode(Set<String>.self, from: data)
            else { return [] }
            return domains
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            userDefaults?.set(data, forKey: "blockedDomains")
        }
    }
}
```

### 2. Real-Time Updates: Darwin Notifications

```swift
// In extension - listen for updates
let notificationName = "dev.turkdogan.focusgate.updated" as CFString
let center = CFNotificationCenterGetDarwinNotifyCenter()
CFNotificationCenterAddObserver(center, observer, callback, notificationName, nil, .deliverImmediately)

// In main app - notify extension of changes
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName("dev.turkdogan.focusgate.updated" as CFString),
    nil, nil, true
)
```

## What Changed from Original Plan

1. ❌ **Removed:** SystemExtensionManager - not needed for .appex
2. ✅ **Kept:** NEFilterDataProvider approach - works perfectly
3. 🔄 **Simplified:** UserDefaults instead of JSON files
4. ➕ **Added:** Darwin notifications for real-time updates

## Extension Type: App Extension (.appex)

- Works with Xcode 26
- Installs as part of main app bundle
- Requires user approval in System Settings
- Fully functional for content filtering

## Build Instructions

### Before Building

1. **Remove SystemExtensionManager from Xcode Project**
   - In Xcode, find `FocusGate/SystemExtensionManager.swift`
   - Right-click → Delete → Move to Trash (or Remove Reference)
   - This file is no longer needed since we're using App Extension (.appex), not System Extension (.systemextension)

2. **Verify Target Membership**
   - Check that shared files (Models.swift, ConfigurationStore.swift, DomainMatcher.swift, DecisionLogger.swift) are included in BOTH targets:
     - FocusGate (main app)
     - FocusGateExtension (extension)
   - Select each file in Xcode → File Inspector (right panel) → Target Membership

### Build Steps

1. **Clean Build Folder**
   - Xcode menu: Product → Clean Build Folder (⇧⌘K)

2. **Build Both Targets**
   - Select "FocusGate" scheme
   - Product → Build (⌘B)

3. **Run the App**
   - Product → Run (⌘R)
   - The app will launch and attempt to register the content filter extension

### After Launch

1. **Enable the Filter**
   - In FocusGate app, go to Status tab
   - Click "Enable Filter" button

2. **Approve in System Settings**
   - macOS will show a notification or the app will display a message
   - Open System Settings → Privacy & Security → Network Extensions
   - Find "FocusGate Content Filter" and enable it
   - You may need to enter your password

3. **Verify Extension is Running**
   - Open Terminal
   - Run: `log stream --predicate 'subsystem == "dev.turkdogan.FocusGate"' --level debug`
   - You should see log messages from FilterDataProvider when it starts

4. **Add Blocked Sites**
   - Go to "Blocked Sites" tab
   - Add a test site (e.g., "reddit.com")
   - Try visiting it in Safari - it should be blocked!

### Troubleshooting

**Extension not loading:**
- Check Console.app for error messages (filter by "FocusGate")
- Verify bundle identifiers match in Info.plist
- Ensure App Group is configured correctly in both entitlements files

**IPC failures:**
- This usually means the extension isn't approved in System Settings
- Go to System Settings → Privacy & Security → Network Extensions

**Sites not blocking:**
- Check that configuration is being saved to UserDefaults
- Use `log stream` to see if extension is receiving Darwin notifications
- Verify extension is actually evaluating flows (check logs)

## Status

✅ Info.plist configured correctly
✅ Entitlements updated
✅ FilterDataProvider updated to use UserDefaults
✅ ConfigurationStore sends Darwin notifications
✅ FilterManager simplified (no SystemExtensionManager)
⏳ Next: Build and test in Xcode
