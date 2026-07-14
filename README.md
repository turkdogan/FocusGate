# FocusGate

A native macOS website blocker that works **system-wide** — every browser, every app — built on Apple's Network Extension framework.

Block distracting sites always or on a weekly schedule, pause with one click from the menubar (locked sites hold through pauses), and get instant "site not found" errors instead of endless loading spinners.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **System-wide blocking** — a Network Extension content filter evaluates every new connection on the Mac at the socket level. Switching browsers or using incognito doesn't bypass it.
- **Instant failure** — a DNS proxy in the same extension answers NXDOMAIN for blocked domains in milliseconds, so browsers show a clean "server not found" page instead of timing out. Non-blocked DNS is forwarded untouched.
- **Schedules** — rule sets with per-weekday time windows (overnight ranges like 22:00–06:00 supported). Sites can be blocked always or only while a rule set is active.
- **Menubar control** — status at a glance, pause for 15 minutes or 1 hour, resume, recent blocks. Pause is enforced by the extension itself, so blocking resumes on schedule even if the app quits.
- **Locked sites** — a commitment device: locked sites stay blocked through pauses and can't be edited or deleted until explicitly unlocked. *This is friction against impulse, not tamper-proofing* — see limitations.
- **Block notifications** — a macOS notification the moment a site is blocked, with a per-site cooldown.
- **Privacy by design** — the extension records blocked attempts only. Allowed traffic (i.e. your browsing) is deliberately never logged anywhere.
- **Self-healing** — the app verifies every configuration push to the extension and automatically restarts the filter session if the channel goes stale (a known macOS issue after extension upgrades).

## Architecture

```
FocusGate.app (SwiftUI, sandboxed)
 ├─ blocklist & schedule management, menubar, notifications
 ├─ NEFilterManager + NEDNSProxyManager configuration
 └─ XPC client ──────────────┐
                             │ mach service (team-ID prefixed)
FocusGateExtension (system extension, runs as root)
 ├─ FilterDataProvider  (NEFilterDataProvider)  – socket-level allow/drop
 ├─ DNSProxyProvider    (NEDNSProxyProvider)    – NXDOMAIN for blocked, forward the rest
 └─ ProviderXPCService  – activity feed + live config updates
```

Configuration flows from app to extension two ways: embedded in the provider configuration's `vendorConfiguration` (survives restarts) and pushed live over XPC (applies immediately). The extension runs as root, so the user's App Group container is *not* shared with it — that's why XPC and vendorConfiguration exist.

## Building

Requirements: Xcode 16+, an Apple Developer account (free won't do — Network Extension entitlements require a paid team).

1. Change the signing team and bundle identifiers (`dev.turkdogan.FocusGate*`) to your own in the project settings, and update the team-ID-prefixed values in `XPCProtocol.swift` (both copies) and the app group in both `.entitlements` files.
2. Build the `FocusGate` scheme.
3. Copy the built `FocusGate.app` to `/Applications` (system extensions only activate from there) and launch it.
4. Click **Enable Filter**, approve the extension in System Settings, and allow the content filter dialog.

During development: **bump `CURRENT_PROJECT_VERSION` every time you change extension code.** macOS stages a copy of the extension and silently keeps running the old one if the version didn't increase.

## Hard-won macOS facts

Things this project learned the painful way — they may save you a day each:

- The system extension bundle's **file name must be its bundle identifier** (`PRODUCT_NAME = $(PRODUCT_BUNDLE_IDENTIFIER)`). Otherwise activation fails with a misleading "Extension not found in App bundle".
- `NEProviderClasses` must be nested inside a **`NetworkExtension` dict** in the extension's Info.plist, with class names via `$(PRODUCT_MODULE_NAME)`.
- The `-systemextension` entitlement variants are **only for Developer ID** distribution; dev and App Store builds use the base values (`content-filter-provider`, `dns-proxy`).
- The extension runs as **root**: `UserDefaults(suiteName:)` App Group sharing with the user's app does not work. Use `vendorConfiguration` + XPC.
- The XPC mach service name must be prefixed with a **team-ID-style app group** (`TEAMID.…`), not an iOS-style `group.…` one — launchd silently refuses to publish otherwise, and the client needs `.privileged`.
- launchd can lose the extension's mach registration after an upgrade ("bootstrap look-up: No such process"); only an extension reload/reboot restores it — hence the app's self-heal path.
- The extension can (and does) **flush the system DNS cache** on config changes so new rules don't wait for TTLs.

## Honest limitations

- **No block page.** For HTTPS, showing custom content in place of a blocked site is exactly what TLS prevents (without MITM-ing your own traffic with a local root CA, which this project refuses to do). Blocked sites show the browser's "can't find server" page.
- **Browsers cling to the past.** A browser's internal DNS cache (~1 min) and already-open connections (until idle) can keep a just-blocked site partially working for a few minutes. Cached page copies can render with no network at all. New connections are always enforced.
- **In-browser DoH** (e.g. Chrome's "secure DNS" pointed at a provider) bypasses the DNS-level instant failure. The socket filter still blocks — it just falls back to the slow-timeout experience.
- **System Settings is the ultimate override.** Any admin can disable the extension there. FocusGate is a productivity tool, not parental controls or MDM.

## Roadmap

- Browser extension companion (friendly block page, catches cached pages)
- Import/export of configuration
- Block-reason visibility everywhere ("blocked by Work Hours")
- Setup wizard + health diagnostics
- Preset blocklists, stronger unlock friction options, macOS Focus integration
- Notarized Developer ID release (entitlement request pending)

## License

MIT — see [LICENSE](LICENSE).
