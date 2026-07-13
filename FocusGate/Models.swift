//
//  Models.swift
//  PageBlocker
//
//  Shared data models for configuration and logging
//

import Foundation

// MARK: - Blocked Site

struct BlockedSite: Codable, Identifiable, Equatable {
    let id: UUID
    var pattern: String           // "example.com" or "*.reddit.com"
    var matchType: MatchType
    var enabled: Bool
    var ruleSetId: UUID?          // nil = always active (no schedule)

    enum MatchType: String, Codable, CaseIterable {
        case exactDomain          // example.com only
        case domainAndSubdomains  // example.com + *.example.com
        case wildcardDomain       // *.example.com (subs only)

        var displayName: String {
            switch self {
            case .exactDomain: return "Exact domain"
            case .domainAndSubdomains: return "Domain + Subdomains"
            case .wildcardDomain: return "Subdomains only"
            }
        }
    }

    init(id: UUID = UUID(), pattern: String, matchType: MatchType, enabled: Bool = true, ruleSetId: UUID? = nil) {
        self.id = id
        self.pattern = pattern
        self.matchType = matchType
        self.enabled = enabled
        self.ruleSetId = ruleSetId
    }
}

// MARK: - Rule Set

struct RuleSet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var schedules: [DaySchedule]

    init(id: UUID = UUID(), name: String, schedules: [DaySchedule] = []) {
        self.id = id
        self.name = name
        self.schedules = schedules
    }

    /// Check if this rule set is currently active based on the schedule
    func isActive(at date: Date, in timezone: TimeZone = .current) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentTime = TimeOfDay(hour: hour, minute: minute)

        // Find matching day schedule
        guard let daySchedule = schedules.first(where: { $0.weekday.rawValue == weekday }) else {
            return false
        }

        // Check if current time falls in any window
        return daySchedule.windows.contains { window in
            window.contains(time: currentTime)
        }
    }
}

// MARK: - Day Schedule

struct DaySchedule: Codable, Identifiable, Equatable {
    let id: UUID
    var weekday: Weekday          // 1=Sunday, 2=Monday, etc.
    var windows: [TimeWindow]

    enum Weekday: Int, Codable, CaseIterable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7

        var displayName: String {
            switch self {
            case .sunday: return "Sunday"
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
            }
        }
    }

    init(id: UUID = UUID(), weekday: Weekday, windows: [TimeWindow] = []) {
        self.id = id
        self.weekday = weekday
        self.windows = windows
    }
}

// MARK: - Time Window

struct TimeWindow: Codable, Identifiable, Equatable {
    let id: UUID
    var start: TimeOfDay
    var end: TimeOfDay

    init(id: UUID = UUID(), start: TimeOfDay, end: TimeOfDay) {
        self.id = id
        self.start = start
        self.end = end
    }

    /// Check if a given time falls within this window (handles overnight windows)
    func contains(time: TimeOfDay) -> Bool {
        if end >= start {
            // Normal window: 09:00 - 17:00
            return time >= start && time <= end
        } else {
            // Overnight window: 22:00 - 06:00
            return time >= start || time <= end
        }
    }

    var isOvernight: Bool {
        return end < start
    }
}

// MARK: - Time of Day

struct TimeOfDay: Codable, Equatable, Comparable {
    var hour: Int                 // 0-23
    var minute: Int               // 0-59

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        return lhs.minute < rhs.minute
    }

    var displayString: String {
        return String(format: "%02d:%02d", hour, minute)
    }

    static var now: TimeOfDay {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

// MARK: - Filter Configuration

struct FilterConfiguration: Codable {
    var blockedSites: [BlockedSite]
    var ruleSets: [RuleSet]
    var version: Int

    /// While set and in the future, the filter allows all traffic. Enforced
    /// by the extension itself so blocking resumes on schedule even if the
    /// app is not running.
    var pausedUntil: Date?

    init(blockedSites: [BlockedSite] = [], ruleSets: [RuleSet] = [], version: Int = 1, pausedUntil: Date? = nil) {
        self.blockedSites = blockedSites
        self.ruleSets = ruleSets
        self.version = version
        self.pausedUntil = pausedUntil
    }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    /// Single source of truth for "should this hostname be blocked right
    /// now" — shared by the socket filter and the DNS proxy so the two
    /// enforcement layers can never disagree.
    func blockDecision(for hostname: String, at date: Date = Date(),
                       timezone: TimeZone = .current) -> (blocked: Bool, ruleSetName: String?) {
        if isPaused { return (false, nil) }

        for site in blockedSites where site.enabled {
            guard DomainMatcher.matches(hostname, pattern: site) else { continue }

            if let ruleSetId = site.ruleSetId {
                guard let ruleSet = ruleSets.first(where: { $0.id == ruleSetId }) else { continue }
                if !ruleSet.isActive(at: date, in: timezone) { continue }
                return (true, ruleSet.name)
            }

            return (true, nil)
        }

        return (false, nil)
    }
}

// MARK: - Decision Log Entry

struct DecisionLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let hostname: String
    let action: Action
    let ruleSetName: String?
    let processName: String?

    enum Action: String, Codable {
        case allow
        case block
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), hostname: String, action: Action, ruleSetName: String? = nil, processName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.hostname = hostname
        self.action = action
        self.ruleSetName = ruleSetName
        self.processName = processName
    }
}

// MARK: - Decision Log

struct DecisionLog: Codable {
    var entries: [DecisionLogEntry]
    var maxEntries: Int

    init(entries: [DecisionLogEntry] = [], maxEntries: Int = 1000) {
        self.entries = entries
        self.maxEntries = maxEntries
    }

    mutating func add(_ entry: DecisionLogEntry) {
        entries.insert(entry, at: 0)

        // Keep only the most recent entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
}
