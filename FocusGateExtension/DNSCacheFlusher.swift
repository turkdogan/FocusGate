//
//  DNSCacheFlusher.swift
//  FocusGateExtension
//
//  Clears the system DNS cache after configuration changes so new rules
//  take effect immediately instead of waiting for cached records to
//  expire. The extension runs as root, so no user interaction is needed.
//  (Browsers keep small internal DNS caches we cannot reach — Chrome's
//  lasts about a minute — but the system layer is the big one.)
//

import Foundation
import os.log

enum DNSCacheFlusher {
    private static let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "DNSCacheFlusher")
    private static let queue = DispatchQueue(label: "dev.turkdogan.FocusGate.dnsflush")
    private static var lastFlush = Date.distantPast

    /// Flushes the system DNS cache, at most once every few seconds so a
    /// burst of config edits does not hammer mDNSResponder.
    static func flush() {
        queue.async {
            guard Date().timeIntervalSince(lastFlush) > 5 else { return }
            lastFlush = Date()

            run("/usr/bin/dscacheutil", ["-flushcache"])
            run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
            os_log("Flushed system DNS cache", log: logger, type: .info)
        }
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            os_log("DNS cache flush step failed (%{public}@): %{public}@",
                   log: logger, type: .error, path, error.localizedDescription)
        }
    }
}
