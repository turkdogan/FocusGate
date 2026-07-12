//
//  XPCProtocol.swift
//  FocusGate
//
//  XPC contract between the main app and the filter extension.
//  The extension runs as root, so file-based sharing through the user's
//  App Group container does not work; XPC over a mach service is the
//  sanctioned channel. Identical copy in app and extension targets.
//

import Foundation

enum FocusGateXPC {
    /// Mach service the extension listens on. Must be prefixed with an
    /// app group from the extension's entitlements or the sandboxed app
    /// is not allowed to connect.
    static let serviceName = "group.dev.turkdogan.focusgate.shared.xpc"

    /// Only clients signed by this team may connect.
    static let codeSigningRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"9B6S2Y8856\""
}

/// Calls the app can make into the running filter provider.
/// Entries travel as JSON-encoded [DecisionLogEntry] to keep the
/// interface at plain NSSecureCoding types.
@objc protocol ProviderCommunication {
    /// Returns entries newer than `sinceTimestamp` (seconds since 1970),
    /// newest first. Pass 0 for everything the provider has.
    func fetchRecentDecisions(sinceTimestamp: Double, reply: @escaping (Data) -> Void)

    func clearDecisions(reply: @escaping (Bool) -> Void)
}
