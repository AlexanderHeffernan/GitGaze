import Testing
import Foundation
@testable import GitGazeCore

struct ContributionTests {
    func day(_ date: String, _ count: Int) -> ContributionDay { .init(date: date, contributionCount: count) }

    @Test func streakSurvivesUntilTodayEndsButNotAnEarlierGap() {
        let days = [day("2026-10-11", 2), day("2026-10-12", 1), day("2026-10-13", 0),
                    day("2026-10-14", 7), day("2026-10-15", 3), day("2026-10-16", 0)]
        let stats = ContributionStats(days: days, today: "2026-10-16")
        #expect(stats.currentStreak == 2)
        #expect(stats.longestStreak == 2)
        #expect(ContributionStats(days: days + [day("2026-10-16", 1)], today: "2026-10-16").currentStreak == 3)
        #expect(ContributionStats(days: days, today: "2026-10-17").currentStreak == 0)
    }

    @Test func recordNeedsToBeatNotTieAndIgnoresFutureAndDuplicateDays() {
        let days = [day("2026-10-13", 20), day("2026-10-15", 3), day("2026-10-16", 19), day("2026-10-17", 900)]
        let tie = ContributionStats(days: days + [day("2026-10-16", 20)], today: "2026-10-16")
        #expect(!tie.isNewRecord)
        #expect(tie.target == 21)
        #expect(tie.todayCount == 20)
        let best = ContributionStats(days: days + [day("2026-10-16", 21)], today: "2026-10-16")
        #expect(best.isNewRecord)
        #expect(best.bestDay == 21)
        #expect(best.progress == 1)
    }

    @Test func missingDatesBreakLongestStreakAndYearBoundaryDoesNot() {
        let stats = ContributionStats(days: [day("2025-12-29", 2), day("2025-12-31", 1), day("2026-01-01", 4), day("2026-01-02", 3)], today: "2026-01-02")
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 3)
        #expect(stats.weekTotal == 10)
    }

    @Test func weeksStartMondayAndDoNotCompareRollingSevenDayWindows() {
        let stats = ContributionStats(days: [day("2026-10-04", 50), day("2026-10-05", 4), day("2026-10-11", 8),
            day("2026-10-12", 2), day("2026-10-16", 3)], today: "2026-10-16")
        #expect(stats.weekTotal == 5)
        #expect(stats.lastWeekTotal == 12)
        #expect(stats.bestWeek == 50)
    }

    @Test func dayArithmeticSurvivesLeapDaysAndAucklandDST() {
        #expect(ContributionStats.offset("2024-03-01", by: -1) == "2024-02-29")
        #expect(ContributionStats.offset("2026-09-27", by: 1) == "2026-09-28")
        let instant = ISO8601DateFormatter().date(from: "2026-10-15T23:30:00Z")!
        #expect(ContributionStats.dayKey(instant, timeZone: TimeZone(identifier: "Pacific/Auckland")!) == "2026-10-16")
        #expect(ContributionStats.dayKey(instant, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-10-15")
    }

    @Test func calendarPeriodCountsAndYearComparisonsAlignAcrossLeapYears() {
        let days = [day("2023-01-01", 7), day("2023-02-28", 5), day("2023-03-01", 11),
            day("2023-03-02", 1000), day("2023-12-31", 200), day("2024-02-28", 2),
            day("2024-02-29", 3), day("2024-03-01", 4), day("2024-03-02", 900)]
        let march = ContributionStats(days: days, today: "2024-03-01")
        #expect(march.todayCount == 4)
        #expect(march.weekTotal == 9)
        #expect(march.monthTotal == 4)
        #expect(march.yearTotal == 9)
        #expect(march.total(inYear: 2023, throughMonthDay: "03-01") == 23)
        #expect(march.total(inYear: 2023) == 1223)
        let leap = ContributionStats(days: days, today: "2024-02-29")
        #expect(leap.monthTotal == 5)
        #expect(leap.total(inYear: 2023, throughMonthDay: "02-29") == 12)
    }

    @Test func emptyHistoryHasAnAchievableFirstTarget() {
        let stats = ContributionStats(days: [], today: "2026-10-16")
        #expect(stats.todayCount == 0)
        #expect(stats.target == 1)
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 0)
        #expect(!stats.isNewRecord)
    }

    @Test func dayArithmeticMatchesTheGregorianCalendarAcrossCenturies() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var date = calendar.date(from: DateComponents(year: 1899, month: 12, day: 25))!
        let end = calendar.date(from: DateComponents(year: 2101, month: 1, day: 8))!
        while date < end {
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            let next = calendar.date(byAdding: .day, value: 1, to: date)!
            let nextParts = calendar.dateComponents([.year, .month, .day], from: next)
            #expect(ContributionStats.offset(key, by: 1) == String(format: "%04d-%02d-%02d", nextParts.year!, nextParts.month!, nextParts.day!))
            let monday = calendar.date(byAdding: .day, value: -((parts.weekday! + 5) % 7), to: date)!
            let mondayParts = calendar.dateComponents([.year, .month, .day], from: monday)
            #expect(ContributionStats.weekStart(key) == String(format: "%04d-%02d-%02d", mondayParts.year!, mondayParts.month!, mondayParts.day!))
            date = calendar.date(byAdding: .day, value: 13, to: date)!
        }
        #expect(ContributionStats.offset("2026-10-16", by: -3650) == "2016-10-18")
        #expect(ContributionStats.offset("not-a-date", by: 1) == "1970-01-02")
    }

    @Test func lookupsAndRangesMatchFullScans() {
        let days = (0..<900).map { day(ContributionStats.offset("2024-01-01", by: $0), ($0 * 7) % 13) }
        let stats = ContributionStats(days: days.shuffled(), today: "2026-03-15")
        #expect(stats.count(on: "2025-06-01") == days.first { $0.date == "2025-06-01" }!.contributionCount)
        #expect(stats.count(on: "2030-01-01") == 0)
        let slice = stats.days(from: "2025-02-27", through: "2025-03-02")
        #expect(slice.map(\.date) == ["2025-02-27", "2025-02-28", "2025-03-01", "2025-03-02"])
        #expect(stats.days(from: "2026-12-01", through: "2026-12-31").isEmpty)
        let scanned = days.filter { $0.date >= "2025-01-01" && $0.date <= "2025-07-04" }.reduce(0) { $0 + $1.contributionCount }
        #expect(stats.total(inYear: 2025, throughMonthDay: "07-04") == scanned)
        #expect(stats.activeDays == days.filter { $0.date <= "2026-03-15" && $0.contributionCount > 0 }.count)
    }

    @Test func contributionCelebrationsIgnoreBaselinesRetriesAndCorrectionsButResetAtMidnight() {
        var tracker = ContributionIncreaseTracker()
        #expect(tracker.observe(day: "2026-10-16", count: 12) == 0)
        #expect(tracker.observe(day: "2026-10-16", count: 15) == 3)
        #expect(tracker.observe(day: "2026-10-16", count: 15) == 0)
        #expect(tracker.observe(day: "2026-10-16", count: 13) == 0)
        #expect(tracker.observe(day: "2026-10-16", count: 15) == 0)
        #expect(tracker.observe(day: "2026-10-16", count: 16) == 1)
        #expect(tracker.observe(day: "2026-10-17", count: 2) == 2)
        #expect(tracker.observe(day: "2026-10-17", count: 2) == 0)
    }
}
