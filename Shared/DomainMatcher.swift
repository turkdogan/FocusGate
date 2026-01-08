//
//  DomainMatcher.swift
//  PageBlocker
//
//  Domain pattern matching logic
//

import Foundation

struct DomainMatcher {

    /// Check if a hostname matches a blocked site pattern
    static func matches(_ hostname: String, pattern: BlockedSite) -> Bool {
        guard pattern.enabled else { return false }

        let normalizedHost = hostname.lowercased()
        let normalizedPattern = pattern.pattern.lowercased()

        switch pattern.matchType {
        case .exactDomain:
            return normalizedHost == normalizedPattern

        case .domainAndSubdomains:
            // Matches example.com and *.example.com
            return normalizedHost == normalizedPattern ||
                   normalizedHost.hasSuffix(".\(normalizedPattern)")

        case .wildcardDomain:
            // Matches *.example.com only (not example.com itself)
            if normalizedPattern.hasPrefix("*.") {
                let baseDomain = String(normalizedPattern.dropFirst(2))
                return normalizedHost.hasSuffix(".\(baseDomain)")
            } else {
                // Treat as subdomain match
                return normalizedHost.hasSuffix(".\(normalizedPattern)")
            }
        }
    }

    /// Extract hostname from a URL string (removing port, path, etc.)
    static func extractHostname(_ urlOrHost: String) -> String? {
        var cleaned = urlOrHost.trimmingCharacters(in: .whitespaces)

        // Add scheme if missing for URL parsing
        if !cleaned.contains("://") {
            cleaned = "https://" + cleaned
        }

        guard let url = URL(string: cleaned),
              let host = url.host else {
            return nil
        }

        return host.lowercased()
    }

    /// Validate a domain pattern
    static func isValidPattern(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return false }

        // Allow wildcard prefix
        let withoutWildcard = trimmed.hasPrefix("*.") ? String(trimmed.dropFirst(2)) : trimmed

        // Basic validation: should contain at least one dot and valid characters
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)

        return predicate.evaluate(with: withoutWildcard)
    }
}
