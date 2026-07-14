//
//  model-tests.swift — unit tests for schedule, matching, and block logic.
//  Run via scripts/run-model-tests.sh (compiles against the app's sources).
//

import Foundation

var passed = 0, failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("  PASS  \(name)") }
    else { failed += 1; print("  FAIL  \(name)") }
}

func date(weekday: Int, hour: Int, minute: Int, tz: TimeZone = TimeZone(identifier: "Europe/Istanbul")!) -> Date {
    // July 2026: the 12th is a Sunday, so weekday N (1=Sun) falls on 11+N
    var comps = DateComponents()
    comps.year = 2026; comps.month = 7; comps.day = 11 + weekday
    comps.hour = hour; comps.minute = minute
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: comps)!
}

let tz = TimeZone(identifier: "Europe/Istanbul")!

// MARK: DomainMatcher

print("== DomainMatcher ==")
let exact = BlockedSite(pattern: "example.com", matchType: .exactDomain)
expect(DomainMatcher.matches("example.com", pattern: exact), "exact matches itself")
expect(!DomainMatcher.matches("www.example.com", pattern: exact), "exact rejects subdomain")
expect(DomainMatcher.matches("EXAMPLE.COM", pattern: exact), "matching is case-insensitive")

let full = BlockedSite(pattern: "reddit.com", matchType: .domainAndSubdomains)
expect(DomainMatcher.matches("reddit.com", pattern: full), "domain+subs matches apex")
expect(DomainMatcher.matches("gql-realtime.reddit.com", pattern: full), "domain+subs matches deep subdomain")
expect(!DomainMatcher.matches("notreddit.com", pattern: full), "domain+subs rejects suffix-similar domain")

let wild = BlockedSite(pattern: "*.example.com", matchType: .wildcardDomain)
expect(DomainMatcher.matches("a.example.com", pattern: wild), "wildcard matches subdomain")
expect(!DomainMatcher.matches("example.com", pattern: wild), "wildcard rejects apex")

let disabled = BlockedSite(pattern: "example.com", matchType: .exactDomain, enabled: false)
expect(!DomainMatcher.matches("example.com", pattern: disabled), "disabled site never matches")

// MARK: TimeWindow

print("== TimeWindow ==")
let day = TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0))
expect(day.contains(time: TimeOfDay(hour: 12, minute: 0)), "normal window: midday inside")
expect(day.contains(time: TimeOfDay(hour: 9, minute: 0)), "normal window: start boundary inclusive")
expect(day.contains(time: TimeOfDay(hour: 17, minute: 0)), "normal window: end boundary inclusive")
expect(!day.contains(time: TimeOfDay(hour: 8, minute: 59)), "normal window: minute before start outside")
expect(!day.contains(time: TimeOfDay(hour: 17, minute: 1)), "normal window: minute after end outside")

let night = TimeWindow(start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 6, minute: 0))
expect(night.isOvernight, "22-06 detected as overnight")
expect(night.contains(time: TimeOfDay(hour: 23, minute: 30)), "overnight: before midnight inside")
expect(night.contains(time: TimeOfDay(hour: 5, minute: 59)), "overnight: early morning inside")
expect(!night.contains(time: TimeOfDay(hour: 12, minute: 0)), "overnight: midday outside")

// MARK: RuleSet.isActive

print("== RuleSet ==")
let workHours = RuleSet(name: "Work", schedules: [2, 3, 4, 5, 6].map {
    DaySchedule(weekday: DaySchedule.Weekday(rawValue: $0)!, windows: [day])
})
expect(workHours.isActive(at: date(weekday: 2, hour: 12, minute: 0), in: tz), "Monday noon active")
expect(!workHours.isActive(at: date(weekday: 2, hour: 18, minute: 0), in: tz), "Monday evening inactive")
expect(!workHours.isActive(at: date(weekday: 1, hour: 12, minute: 0), in: tz), "Sunday noon inactive")
expect(!workHours.isActive(at: date(weekday: 7, hour: 12, minute: 0), in: tz), "Saturday noon inactive")

// Overnight semantics: a 22-06 window on Monday covers Monday 00-06 and
// Monday 22-24 — NOT Tuesday morning. Documented behavior.
let monNight = RuleSet(name: "MonNight", schedules: [DaySchedule(weekday: .monday, windows: [night])])
expect(monNight.isActive(at: date(weekday: 2, hour: 23, minute: 0), in: tz), "overnight: Monday 23:00 active")
expect(monNight.isActive(at: date(weekday: 2, hour: 5, minute: 0), in: tz), "overnight: Monday 05:00 active")
expect(!monNight.isActive(at: date(weekday: 3, hour: 5, minute: 0), in: tz), "overnight: Tuesday 05:00 NOT active (per-day windows)")

// Timezone honesty: Monday noon Istanbul is not Monday noon in Tokyo terms
expect(workHours.isActive(at: date(weekday: 2, hour: 12, minute: 0), in: tz)
       != workHours.isActive(at: date(weekday: 2, hour: 23, minute: 30), in: tz),
       "different times evaluate differently")

// MARK: FilterConfiguration.blockDecision

print("== blockDecision ==")
var lockedSite = BlockedSite(pattern: "locked.com", matchType: .domainAndSubdomains)
lockedSite.locked = true

var config = FilterConfiguration(
    blockedSites: [
        BlockedSite(pattern: "always.com", matchType: .domainAndSubdomains),
        BlockedSite(pattern: "scheduled.com", matchType: .domainAndSubdomains, ruleSetId: workHours.id),
        lockedSite,
    ],
    ruleSets: [workHours]
)

let monNoon = date(weekday: 2, hour: 12, minute: 0)
let monEve  = date(weekday: 2, hour: 20, minute: 0)

expect(config.blockDecision(for: "always.com", at: monNoon, timezone: tz).blocked, "always-site blocked")
expect(config.blockDecision(for: "sub.always.com", at: monNoon, timezone: tz).blocked, "subdomain blocked")
expect(!config.blockDecision(for: "other.com", at: monNoon, timezone: tz).blocked, "unlisted site allowed")

let d1 = config.blockDecision(for: "scheduled.com", at: monNoon, timezone: tz)
expect(d1.blocked && d1.ruleSetName == "Work", "scheduled site blocked in window with rule name")
expect(!config.blockDecision(for: "scheduled.com", at: monEve, timezone: tz).blocked, "scheduled site allowed outside window")

config.pausedUntil = Date().addingTimeInterval(600)
expect(!config.blockDecision(for: "always.com", at: monNoon, timezone: tz).blocked, "pause releases ordinary site")
expect(config.blockDecision(for: "locked.com", at: monNoon, timezone: tz).blocked, "pause does NOT release locked site")

config.pausedUntil = Date().addingTimeInterval(-1)
expect(config.blockDecision(for: "always.com", at: monNoon, timezone: tz).blocked, "expired pause resumes blocking")

// Dangling rule set reference: site is skipped, not blocked
let dangling = FilterConfiguration(
    blockedSites: [BlockedSite(pattern: "ghost.com", matchType: .exactDomain, ruleSetId: UUID())],
    ruleSets: []
)
expect(!dangling.blockDecision(for: "ghost.com", at: monNoon, timezone: tz).blocked, "dangling rule set reference does not block")

print("")
print("=== \(passed) passed, \(failed) failed ===")
exit(failed > 0 ? 1 : 0)
