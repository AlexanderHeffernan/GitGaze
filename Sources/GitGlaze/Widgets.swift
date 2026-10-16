import SwiftUI
import GitGlazeCore

struct TodayCard: View {
    let stats: ContributionStats
    let historyLabel: String
    var historyComplete = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Card {
            HStack {
                sectionHeading("TODAY")
                Spacer()
                Text(Date(), format: .dateTime.month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ZStack {
                    RecordDial(progress: stats.progress, active: stats.todayCount > 0, record: stats.isNewRecord)
                    VStack(spacing: 1) {
                        Text(stats.todayCount.formatted()).font(.system(size: stats.todayCount > 99 ? 32 : 40, weight: .medium, design: .rounded))
                            .tracking(-2).contentTransition(.numericText())
                        Text("today").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }.frame(width: 112, height: 112).accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stats.todayCount) contributions today. \(Int(stats.progress * 100)) percent of your next daily record.")
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stats.isNewRecord ? "NEW DAILY BEST" : "DAILY BEST")
                            .font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(stats.isNewRecord ? Theme.gold : Color.secondary)
                        if !historyComplete { Text("Past year only").font(.system(size: 9)).foregroundStyle(.secondary) }
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(stats.bestDay.formatted()).font(.system(size: 25, weight: .medium)).tracking(-0.8)
                            Text("contributions").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }.help(historyLabel)
                    if !stats.isNewRecord {
                        Text("\(max(0, stats.target - stats.todayCount)) to beat it").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    } else {
                        Label("+\(stats.todayCount - stats.previousBest) above previous", systemImage: "arrow.up.right")
                            .font(.system(size: 10)).foregroundStyle(Theme.gold)
                    }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 2)
        }.animation(reduceMotion ? nil : .spring(duration: 0.5), value: stats.todayCount)
    }
}

struct StreakCard: View {
    let stats: ContributionStats
    var body: some View {
        Card {
            sectionHeading("STREAK")
            HStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(stats.currentStreak)").font(.system(size: 28, weight: .medium)).tracking(-1)
                    Text("days").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(0..<7) { index in
                        let key = ContributionStats.offset(stats.today, by: index - 6)
                        let active = (stats.days.first { $0.date == key }?.contributionCount ?? 0) > 0
                        Capsule().fill(active ? Theme.accent : Color.primary.opacity(0.07))
                            .overlay(Capsule().strokeBorder(index == 6 ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1))
                            .frame(width: 6, height: index == 6 ? 22 : 16)
                            .help("\(key): \(active ? "Active" : "No contributions")")
                    }
                }
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(stats.longestStreak)").font(.system(size: 20, weight: .medium)).tracking(-0.5)
                    Text("best").font(.system(size: 9)).foregroundStyle(.secondary)
                }.frame(width: 44)
            }
        }
    }
}

struct HistoryOptions: View {
    @AppStorage("historyWeeks") private var weeks = 53
    var body: some View {
        ChoiceStrip(title: "Visible history", selection: $weeks, options: [(26, "6 months"), (53, "Year")])
    }
}

struct HistoryCard: View {
    let profile: Profile
    let today: String
    @AppStorage("historyWeeks") private var weeks = 53
    var body: some View {
        Card {
            sectionHeading("CONTRIBUTIONS")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(profile.totalContributions.formatted()).font(.system(size: 24, weight: .medium)).tracking(-0.8)
                Text("past year").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Heatmap(days: profile.days, today: today, weeks: weeks).frame(height: weeks == 53 ? 59 : 94)
        }
    }
}

func heatColor(_ level: Int) -> Color {
    level == 0 ? Color.primary.opacity(0.06) : Theme.accent.opacity([0, 0.22, 0.42, 0.67, 1][min(4, max(0, level))])
}

struct Heatmap: View {
    let days: [ContributionDay]
    let today: String
    let weeks: Int
    var showDates = true
    @State private var hovered: ContributionDay?
    private var cells: [ContributionDay?] {
        let endDate = ISO8601DateFormatter().date(from: today + "T12:00:00Z") ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = calendar.component(.weekday, from: endDate) - 1
        let start = ContributionStats.offset(today, by: -(weeks - 1) * 7 - weekday)
        let indexed = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<(weeks * 7)).map { index in
            let key = ContributionStats.offset(start, by: index)
            return key <= today ? indexed[key] ?? ContributionDay(date: key, contributionCount: 0) : nil
        }
    }
    var body: some View {
        let cells = cells
        GeometryReader { geometry in
            let pitch = geometry.size.width / CGFloat(weeks)
            let size = max(1, min(pitch - 1.7, (geometry.size.height - (showDates ? 16 : 0)) / 7 - 1.7))
            VStack(alignment: .leading, spacing: 5) {
                Canvas { context, _ in
                    for (index, day) in cells.enumerated() {
                        guard let day else { continue }
                        let rect = CGRect(x: CGFloat(index / 7) * pitch, y: CGFloat(index % 7) * (size + 1.7), width: size, height: size)
                        let level: Int = switch day.color.lowercased() {
                        case "#9be9a8", "#0e4429": 1
                        case "#40c463", "#006d32": 2
                        case "#30a14e", "#26a641": 3
                        case "#216e39", "#39d353": 4
                        default: day.contributionCount > 0 ? min(4, max(1, day.contributionCount / 5 + 1)) : 0
                        }
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(heatColor(level)))
                        if hovered?.date == day.date { context.stroke(Path(roundedRect: rect.insetBy(dx: -0.4, dy: -0.4), cornerRadius: 1.5), with: .color(.primary.opacity(0.65)), lineWidth: 0.7) }
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let column = Int(location.x / pitch), row = Int(location.y / (size + 1.7))
                        let index = column * 7 + row
                        hovered = row >= 0 && row < 7 && column >= 0 && column < weeks && cells.indices.contains(index) ? cells[index] : nil
                    case .ended: hovered = nil
                    }
                }.help(hovered.map { "\($0.contributionCount) contributions · \($0.date)" } ?? "Contribution history")
                    .accessibilityLabel("\(weeks)-week contribution graph")
                if showDates {
                    HStack {
                        Text(hovered.map { "\($0.contributionCount) contributions · \($0.date)" } ?? String(ContributionStats.offset(today, by: -(weeks - 1) * 7).prefix(7)))
                        Spacer()
                        if hovered == nil { Text("Today") }
                    }.font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MomentumCard: View {
    let stats: ContributionStats
    let days: [ContributionDay]
    let today: String
    var body: some View {
        Card {
            sectionHeading("THIS WEEK")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(stats.weekTotal)").font(.system(size: 28, weight: .medium)).tracking(-1)
                Text("contributions").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.lastWeekTotal) last week").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            let start = ContributionStats.weekStart(today)
            let indexed = Dictionary(days.map { ($0.date, $0.contributionCount) }, uniquingKeysWith: { _, last in last })
            let values = (0..<7).map { indexed[ContributionStats.offset(start, by: $0)] ?? 0 }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7) { index in
                    VStack(spacing: 5) {
                        Text("\(values[index])").font(.system(size: 8)).foregroundStyle(.secondary)
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(Theme.accent.gradient.opacity(values[index] > 0 ? 0.9 : 0.15))
                            .frame(height: max(3, 42 * CGFloat(values[index]) / CGFloat(max(1, values.max() ?? 1))))
                        Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.system(size: 9)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 70).help("Monday–Sunday · this week so far versus all of last week")
        }
    }
}

struct RecordsCard: View {
    let stats: ContributionStats
    var body: some View {
        Card {
            sectionHeading("PERSONAL BESTS")
            HStack {
                record("Day", stats.bestDay, "contributions")
                Spacer()
                record("Week", stats.bestWeek, "contributions")
                Spacer()
                record("Streak", stats.longestStreak, "days")
            }
        }
    }
    private func record(_ title: String, _ value: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(size: 26, weight: .medium)).tracking(-1)
            Text(unit).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
}

struct YearComparisonOptions: View {
    @ObservedObject var store: Store
    @AppStorage("comparisonYear") private var selectedYear = 0
    @AppStorage("comparisonMode") private var mode = "ytd"
    var body: some View {
        VStack(spacing: 14) {
            ChoiceMenu(title: "Compare with", selection: $selectedYear, options: [(0, "Previous year")] +
                (store.dashboard?.profile.years ?? []).filter { $0 < Int(store.today.prefix(4))! }.sorted(by: >).map { ($0, String($0)) })
            ChoiceStrip(title: "Period", selection: $mode, options: [("ytd", "Same point in year"), ("full", "Full years")])
        }
    }
}

struct YearComparisonCard: View {
    @ObservedObject var store: Store
    @AppStorage("comparisonYear") private var selectedYear = 0
    @AppStorage("comparisonMode") private var mode = "ytd"
    var body: some View {
        Card {
            sectionHeading("YEAR IN PERSPECTIVE")
            if let stats = store.stats, let dashboard = store.dashboard {
                let year = Int(store.today.prefix(4))!
                let previous = dashboard.profile.years.contains(selectedYear) && selectedYear < year ? selectedYear : year - 1
                let cutoff = mode == "ytd" ? String(store.today.suffix(5)) : "12-31"
                let current = stats.yearTotal
                let older = stats.total(inYear: previous, throughMonthDay: cutoff)
                if dashboard.historyComplete {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(current.formatted()).font(.system(size: 28, weight: .medium)).tracking(-1)
                        Text(String(year)).font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(current >= older ? "+" : "−")\(abs(current - older).formatted())")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                    cumulativeChart(stats: stats, year: year, previous: previous, cutoff: cutoff)
                        .frame(height: 100).padding(.vertical, 6)
                    HStack {
                        Label(String(year) + " · " + current.formatted(), systemImage: "circle.fill").foregroundStyle(Theme.accent)
                        Spacer()
                        Text(String(previous) + " · " + older.formatted()).foregroundStyle(.secondary)
                    }.font(.system(size: 10))
                    Text(mode == "ytd" ? "Both years through \(store.now.formatted(.dateTime.month(.abbreviated).day()))" : "Current year to date · previous full year")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                } else {
                    Text(store.loadingHistory ? "Loading yearly history…" : "Yearly history unavailable. Refresh to try again.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 18)
                }
            }
        }
    }

    private func position(_ monthDay: String) -> Double {
        let parts = monthDay.split(separator: "-").compactMap { Int($0) }
        return Double([0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335][parts[0] - 1] + parts[1])
    }

    private func cumulativeChart(stats: ContributionStats, year: Int, previous: Int, cutoff: String) -> some View {
        let maximum = Double(max(1, stats.yearTotal, stats.total(inYear: previous, throughMonthDay: cutoff)))
        let end = position(cutoff)
        return Canvas { context, size in
            for index in 0..<3 {
                let y = size.height * CGFloat(index) / 2
                var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.06)), lineWidth: 0.5)
            }
            for value in [previous, year] {
                var count = 0
                var line = Path(); line.move(to: CGPoint(x: 0, y: size.height))
                var last = CGPoint(x: 0, y: size.height)
                for day in stats.days where day.date.hasPrefix("\(value)-") && String(day.date.suffix(5)) <= cutoff {
                    count += day.contributionCount
                    last = CGPoint(x: position(String(day.date.suffix(5))) / end * size.width, y: size.height * (1 - Double(count) / maximum))
                    line.addLine(to: last)
                }
                if value == year {
                    var area = line; area.addLine(to: CGPoint(x: last.x, y: size.height)); area.closeSubpath()
                    context.fill(area, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0.17), Theme.accent.opacity(0.01)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                context.stroke(line, with: .color(value == year ? Theme.accent : .secondary.opacity(0.65)), style: StrokeStyle(lineWidth: value == year ? 2 : 1.2, lineCap: .round, lineJoin: .round, dash: value == year ? [] : [3, 3]))
            }
        }.accessibilityLabel("\(year) and \(previous) cumulative contributions, \(mode == "ytd" ? "same point in each year" : "full years")")
    }
}
