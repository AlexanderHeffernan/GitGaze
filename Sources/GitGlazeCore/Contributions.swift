import Foundation

/// Tracks a day's high-water mark so retries and downward API corrections don't celebrate twice.
public struct ContributionIncreaseTracker: Sendable {
    private var day: String?
    private var highest = 0

    public init() {}

    public mutating func observe(day: String, count: Int) -> Int {
        guard let previousDay = self.day else {
            self.day = day
            highest = count
            return 0 // Initial sign-in is a baseline, not newly detected work.
        }
        if previousDay != day {
            self.day = day
            highest = 0
        }
        let increase = max(0, count - highest)
        highest = max(highest, count)
        return increase
    }
}

public struct ContributionDay: Codable, Equatable, Sendable, Identifiable {
    public var date: String
    public var contributionCount: Int
    public var color: String
    public var id: String { date }

    public init(date: String, contributionCount: Int, color: String = "#ebedf0") {
        self.date = date
        self.contributionCount = contributionCount
        self.color = color
    }
}

public struct Person: Codable, Identifiable, Sendable {
    public var login: String
    public var name: String?
    public var avatarUrl: String
    public var id: String { login }
    public var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? login }
}

public struct Profile: Codable, Sendable {
    public var person: Person
    public var days: [ContributionDay]
    public var years: [Int]
    public var totalContributions: Int
    public var restrictedCount: Int
}

public struct Dashboard: Codable, Sendable {
    public var profile: Profile
    public var history: [ContributionDay]
    public var historyComplete: Bool
    public var following: [Person]
    public var people: [String: Profile]
    public var updatedAt: Date

    public init(profile: Profile, history: [ContributionDay], historyComplete: Bool,
                following: [Person], people: [String: Profile], updatedAt: Date) {
        self.profile = profile
        self.history = history
        self.historyComplete = historyComplete
        self.following = following
        self.people = people
        self.updatedAt = updatedAt
    }
}

/// Uses GitHub's day buckets unchanged: never rebins commits or guesses private activity.
public struct ContributionStats: Sendable {
    public let days: [ContributionDay]
    public let today: String

    public init(days: [ContributionDay], today: String) {
        var unique: [String: ContributionDay] = [:]
        for day in days where day.date <= today { unique[day.date] = day }
        self.days = unique.values.sorted { $0.date < $1.date }
        self.today = today
    }

    public var todayCount: Int { days.first { $0.date == today }?.contributionCount ?? 0 }
    public var previousBest: Int { days.filter { $0.date < today }.map(\.contributionCount).max() ?? 0 }
    public var bestDay: Int { max(previousBest, todayCount) }
    public var isNewRecord: Bool { todayCount > 0 && todayCount > previousBest }
    public var target: Int { previousBest + 1 }
    public var progress: Double { min(1, Double(todayCount) / Double(target)) }

    public var currentStreak: Int {
        let counts = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.contributionCount) })
        var cursor = todayCount > 0 ? today : Self.offset(today, by: -1)
        var count = 0
        while (counts[cursor] ?? 0) > 0 {
            count += 1
            cursor = Self.offset(cursor, by: -1)
        }
        return count
    }

    public var longestStreak: Int {
        var longest = 0
        var run = 0
        var previous: String?
        for day in days {
            if let previous, Self.offset(previous, by: 1) != day.date { run = 0 }
            run = day.contributionCount > 0 ? run + 1 : 0
            longest = max(longest, run)
            previous = day.date
        }
        return longest
    }

    public var weekTotal: Int { total(from: Self.weekStart(today), through: today) }
    public var monthTotal: Int { total(from: String(today.prefix(7)) + "-01", through: today) }
    public var yearTotal: Int { total(from: String(today.prefix(4)) + "-01-01", through: today) }
    /// Compare calendar years through the same month/day, rather than a leap-sensitive day offset.
    public func total(inYear year: Int, throughMonthDay: String? = nil) -> Int {
        total(from: "\(year)-01-01", through: "\(year)-" + (throughMonthDay ?? "12-31"))
    }
    public var lastWeekTotal: Int {
        let start = Self.weekStart(today)
        return total(from: Self.offset(start, by: -7), through: Self.offset(start, by: -1))
    }
    public var bestWeek: Int {
        Dictionary(grouping: days, by: { Self.weekStart($0.date) })
            .values.map { $0.reduce(0) { $0 + $1.contributionCount } }.max() ?? 0
    }
    public var activeDays: Int { days.filter { $0.contributionCount > 0 }.count }

    private func total(from: String, through: String) -> Int {
        days.filter { $0.date >= from && $0.date <= through }.reduce(0) { $0 + $1.contributionCount }
    }

    public static func dayKey(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    // Date-only arithmetic in UTC avoids DST and locale-dependent week boundaries.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func parse(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    public static func offset(_ key: String, by count: Int) -> String {
        dayKey(calendar.date(byAdding: .day, value: count, to: parse(key))!, timeZone: calendar.timeZone)
    }

    public static func weekStart(_ key: String) -> String {
        let weekday = calendar.component(.weekday, from: parse(key))
        return offset(key, by: -((weekday + 5) % 7))
    }
}
