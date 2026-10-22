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
/// Every derived figure is computed once here, so views and the menu bar can read them freely.
public struct ContributionStats: Sendable {
    public let days: [ContributionDay]
    public let today: String
    public let todayCount: Int
    public let previousBest: Int
    public let currentStreak: Int
    public let longestStreak: Int
    public let bestWeek: Int
    public let activeDays: Int
    public let weekTotal: Int
    public let lastWeekTotal: Int
    public let monthTotal: Int
    public let yearTotal: Int
    private let counts: [String: Int]
    /// `runningTotals[i]` is the sum of `days[..<i]`, so any date range costs two binary searches.
    private let runningTotals: [Int]

    public init(days: [ContributionDay], today: String) {
        var unique: [String: ContributionDay] = [:]
        unique.reserveCapacity(days.count)
        for day in days where day.date <= today { unique[day.date] = day }
        let sorted = unique.values.sorted { $0.date < $1.date }
        self.days = sorted
        self.today = today

        var counts: [String: Int] = [:]
        counts.reserveCapacity(sorted.count)
        var runningTotals = [0]
        runningTotals.reserveCapacity(sorted.count + 1)
        var weeks: [Int: Int] = [:]
        var previousBest = 0, longest = 0, run = 0, active = 0
        var previous: Int?
        for day in sorted {
            let number = Self.dayNumber(day.date)
            counts[day.date] = day.contributionCount
            runningTotals.append(runningTotals[runningTotals.count - 1] + day.contributionCount)
            weeks[number - Self.daysSinceMonday(number), default: 0] += day.contributionCount
            if day.date < today { previousBest = max(previousBest, day.contributionCount) }
            if day.contributionCount > 0 { active += 1 }
            if let previous, previous + 1 != number { run = 0 }
            run = day.contributionCount > 0 ? run + 1 : 0
            longest = max(longest, run)
            previous = number
        }
        self.counts = counts
        self.runningTotals = runningTotals
        self.previousBest = previousBest
        self.longestStreak = longest
        self.bestWeek = weeks.values.max() ?? 0
        self.activeDays = active

        let todayCount = counts[today] ?? 0
        self.todayCount = todayCount
        let todayNumber = Self.dayNumber(today)
        var cursor = todayCount > 0 ? todayNumber : todayNumber - 1
        var streak = 0
        while (counts[Self.key(forDayNumber: cursor)] ?? 0) > 0 {
            streak += 1
            cursor -= 1
        }
        self.currentStreak = streak

        let weekStart = todayNumber - Self.daysSinceMonday(todayNumber)
        let weekKey = Self.key(forDayNumber: weekStart)
        weekTotal = Self.sum(sorted, runningTotals, from: weekKey, through: today)
        lastWeekTotal = Self.sum(sorted, runningTotals, from: Self.key(forDayNumber: weekStart - 7), through: Self.key(forDayNumber: weekStart - 1))
        monthTotal = Self.sum(sorted, runningTotals, from: String(today.prefix(7)) + "-01", through: today)
        yearTotal = Self.sum(sorted, runningTotals, from: String(today.prefix(4)) + "-01-01", through: today)
    }

    public var bestDay: Int { max(previousBest, todayCount) }
    public var isNewRecord: Bool { todayCount > 0 && todayCount > previousBest }
    public var target: Int { previousBest + 1 }
    public var progress: Double { min(1, Double(todayCount) / Double(target)) }

    /// GitHub's count for a day key, or zero when the calendar has no bucket for it.
    public func count(on date: String) -> Int { counts[date] ?? 0 }

    /// Days in an inclusive date-key range, already in calendar order.
    public func days(from: String, through: String) -> ArraySlice<ContributionDay> {
        let range = Self.indices(days, from: from, through: through)
        return days[range]
    }

    /// Compare calendar years through the same month/day, rather than a leap-sensitive day offset.
    public func total(inYear year: Int, throughMonthDay: String? = nil) -> Int {
        Self.sum(days, runningTotals, from: "\(year)-01-01", through: "\(year)-" + (throughMonthDay ?? "12-31"))
    }

    private static func indices(_ days: [ContributionDay], from: String, through: String) -> Range<Int> {
        let lower = boundary(days) { $0 < from }
        let upper = boundary(days) { $0 <= through }
        return lower..<max(lower, upper)
    }

    /// First index whose date no longer satisfies `belongsBefore`.
    private static func boundary(_ days: [ContributionDay], _ belongsBefore: (String) -> Bool) -> Int {
        var low = 0, high = days.count
        while low < high {
            let middle = (low + high) / 2
            if belongsBefore(days[middle].date) { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private static func sum(_ days: [ContributionDay], _ runningTotals: [Int], from: String, through: String) -> Int {
        let range = indices(days, from: from, through: through)
        return runningTotals[range.upperBound] - runningTotals[range.lowerBound]
    }

    public static func dayKey(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    // Date-only arithmetic on proleptic Gregorian day numbers avoids DST, locale and Calendar allocation.
    // Unparseable keys fall back to 1970-01-01, matching the previous Calendar-based behaviour.
    public static func offset(_ key: String, by count: Int) -> String {
        Self.key(forDayNumber: dayNumber(key) + count)
    }

    public static func weekStart(_ key: String) -> String {
        let number = dayNumber(key)
        return Self.key(forDayNumber: number - daysSinceMonday(number))
    }

    /// Days since 1970-01-01 for a `YYYY-MM-DD` key.
    static func dayNumber(_ key: String) -> Int {
        var parts = [0, 0, 0], index = 0, digits = 0
        for byte in key.utf8 {
            if byte == UInt8(ascii: "-") {
                guard digits > 0, index < 2 else { return 0 }
                index += 1; digits = 0
            } else if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                parts[index] = parts[index] * 10 + Int(byte - UInt8(ascii: "0")); digits += 1
            } else { return 0 }
        }
        guard index == 2, digits > 0, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return 0 }
        // Howard Hinnant's days_from_civil.
        let year = parts[1] <= 2 ? parts[0] - 1 : parts[0]
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (parts[1] + (parts[1] > 2 ? -3 : 9)) + 2) / 5 + parts[2] - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func key(forDayNumber number: Int) -> String {
        // Howard Hinnant's civil_from_days.
        let shifted = number + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return key(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    /// 0 for Monday through 6 for Sunday. 1970-01-01 was a Thursday.
    private static func daysSinceMonday(_ number: Int) -> Int {
        ((number + 3) % 7 + 7) % 7
    }

    private static func key(year: Int, month: Int, day: Int) -> String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
        }
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
    }
}
