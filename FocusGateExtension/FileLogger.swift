//
//  FileLogger.swift
//  FocusGateExtension
//
//  Simple file logger for debugging
//

import Foundation

class FileLogger {
    private let fileURL: URL
    
    init() {
        // Write to App Group container
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.dev.turkdogan.focusgate.shared"
        ) {
            self.fileURL = containerURL.appendingPathComponent("extension-debug.log")
        } else {
            // Fallback to temp
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("extension-debug.log")
        }
        
        // Clear old log on init
        try? "=== Extension started at \(Date()) ===\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            // File doesn't exist, create it
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
