#if DEBUG
import AppKit
import SwiftUI
import GitGazeCore

extension AppDelegate {
    func review(in directory: String) async {
        let path = { (name: String) in directory + "/" + name + ".png" }
        let appearance = store.appearance, palette = store.palette
        let customLight = store.customLight, customDark = store.customDark, reminder = store.reminder
        let appAppearance = NSApp.appearance
        let hidden = store.hidden, settings = store.settings
        store.appearance = "system"
        store.settings = false
        defer {
            store.appearance = appearance; store.palette = palette; store.hidden = hidden
            store.customLight = customLight; store.customDark = customDark; store.reminder = reminder
            store.settings = settings; NSApp.appearance = appAppearance
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await captureReview(DashboardView(store: store), to: path("dashboard-dark"))
        NSApp.appearance = NSAppearance(named: .aqua)
        await captureReview(DashboardView(store: store), to: path("dashboard-light"))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        store.hidden.formUnion(["favourites", "momentum", "records", "people"])
        await captureReview(DashboardView(store: store, adding: true), to: path("widgets"))
        store.hidden = hidden
        store.settings = true
        await captureReview(DashboardView(store: store), to: path("settings"))
        store.settings = false
        await captureReview(DashboardScroll { PeopleCard(store: store, favouritesOnly: true).padding(.horizontal, 22) }
            .frame(width: Theme.width, height: Theme.height).background(Theme.background), to: path("people"))
        await captureReview(DashboardScroll {
            WidgetShell(module: .favourites, store: store, configuring: true, configure: {}).padding(.horizontal, 22)
        }.frame(width: Theme.width, height: Theme.height).background(Theme.background), to: path("people-settings"))
        await captureReview(PeopleSettings(store: store, search: "zz-no-match").padding(22)
            .frame(width: Theme.width, height: 200).background(Theme.background), to: path("people-search"))
        if let person = store.orderedPeople.first, let profile = store.dashboard?.people[person.login] {
            await captureReview(VStack(alignment: .leading, spacing: 16) {
                sectionHeading("EXPANDED HISTORY")
                PersonRow(person: person, profile: profile, today: store.today, expanded: true)
            }.padding(22).frame(width: Theme.width).background(Theme.background), to: path("person-expanded"))
        }
        let today = store.today
        await captureReview(VStack(spacing: 0) {
            Text("SAMPLE DATA").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach([0, 1, 21], id: \.self) { count in
                TodayCard(stats: ContributionStats(days: [ContributionDay(date: ContributionStats.offset(today, by: -1), contributionCount: 20),
                    ContributionDay(date: today, contributionCount: count)], today: today), historyLabel: "Sample history")
            }
        }.padding(.horizontal, 22).frame(width: Theme.width).background(Theme.background), to: path("milestones"))
        if let stats = store.stats, let dashboard = store.dashboard {
            await captureReview(VStack(spacing: 0) {
                MomentumCard(stats: stats, today: today)
                RecordsCard(stats: stats)
                HistoryOptions()
            }.padding(22).frame(width: Theme.width).background(Theme.background), to: path("weekly-records"))
        }
        await captureReview(menuExamples, to: path("menu-dark"))
        NSApp.appearance = NSAppearance(named: .aqua)
        await captureReview(menuExamples, to: path("menu-light"))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        store.palette = "violet"
        await captureReview(DashboardView(store: store), to: path("dashboard-violet"))
        store.palette = "coral"
        await captureReview(DashboardView(store: store), to: path("dashboard-coral"))
        store.palette = "ice"
        await captureReview(DashboardView(store: store), to: path("dashboard-ice"))
        store.palette = "graphite"
        await captureReview(DashboardView(store: store), to: path("dashboard-graphite"))
        store.palette = "mint"
        await captureReview(DashboardView(store: store), to: path("dashboard-mint"))
        for name in ["rose", "amber", "cobalt", "orchid", "lagoon"] {
            store.palette = name
            await captureReview(DashboardView(store: store), to: path("dashboard-" + name))
        }
        store.palette = palette
        await captureReview(DashboardView(store: store, widgetSettings: .streak), to: path("streak-settings"))
        await captureReview(YearComparisonCard(store: store).padding(22).frame(width: Theme.width).background(Theme.background), to: path("years"))
        let comparisonMode = UserDefaults.standard.string(forKey: "comparisonMode")
        UserDefaults.standard.set("full", forKey: "comparisonMode")
        await captureReview(YearComparisonCard(store: store).padding(22).frame(width: Theme.width).background(Theme.background), to: path("years-full"))
        if let comparisonMode { UserDefaults.standard.set(comparisonMode, forKey: "comparisonMode") }
        else { UserDefaults.standard.removeObject(forKey: "comparisonMode") }
        await captureReview(WidgetShell(module: .years, store: store, configuring: true, configure: {}).padding(22)
            .frame(width: Theme.width).background(Theme.background), to: path("year-settings"))
        await captureReview(SettingsView(store: store).padding(.horizontal, 22).frame(width: Theme.width).background(Theme.background), to: path("settings-full"), height: 940)
        store.palette = "custom"; store.customDark = "F6A553"; store.customLight = "995215"
        await captureReview(SettingsView(store: store).padding(.horizontal, 22).frame(width: Theme.width).background(Theme.background), to: path("custom-settings"), height: 1100)
        await captureReview(DashboardView(store: store), to: path("custom-dark"))
        NSApp.appearance = NSAppearance(named: .aqua)
        await captureReview(DashboardView(store: store), to: path("custom-light"))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        store.palette = palette; store.customLight = customLight; store.customDark = customDark
        store.reminder = true
        await captureReview(WidgetShell(module: .streak, store: store, configuring: true, configure: {}).padding(22)
            .frame(width: Theme.width).background(Theme.background), to: path("reminder-picker"), height: 200)
        store.reminder = reminder
        await captureReview(WidgetShell(module: .heatmap, store: store, configuring: true, configure: {}).padding(22)
            .frame(width: Theme.width).background(Theme.background), to: path("history-picker"), height: 200)
        await captureReview(CelebrationView(count: 3, record: false, sample: true).background(Theme.background), to: path("celebration"), width: 440, height: 340, delay: 2.5)
        for name in ["nova", "meteors"] {
            await captureReview(CelebrationView(count: 3, record: false, sample: true, style: name).background(Theme.background), to: path("celebration-" + name), width: 440, height: 340, delay: 2.5)
        }
        await captureReview(CelebrationView(count: 1, record: true, sample: true, animated: false).background(Theme.background), to: path("celebration-reduced"), width: 440, height: 90)
        await captureReview(WelcomeView(store: store).padding(22).frame(width: Theme.width, height: Theme.height).background(Theme.background), to: path("welcome"))
        let wasLoading = store.loading
        store.loading = true
        await captureReview(DashboardView(store: store), to: path("refreshing"))
        store.loading = wasLoading
        let keyWindow = NSApp.keyWindow
        store.showCelebration(count: 3, record: false, sample: true)
        updateStatus()
        if let panel = celebrationPanel {
            assert(panel.ignoresMouseEvents && NSApp.keyWindow === keyWindow)
            await captureWindow(panel, to: path("celebration-live"), delay: 1.3)
        }
        let flip = ReviewFlipState()
        await captureMotion(ReviewFlipView(store: store, state: flip), name: "widget-flip", directory: directory) { frame in
            if frame == 6 { flip.flipped = true }
            if frame == 24 { flip.flipped = false }
        }
        let layout = store.modules
        store.hidden = Set(Module.allCases.filter { ![.today, .streak, .heatmap].contains($0) }.map(\.rawValue))
        await captureMotion(DashboardView(store: store), name: "widget-reorder", directory: directory) { frame in
            if frame == 6, let first = store.visibleModules.first { store.moveModule(first, by: 1) }
            if frame == 24 { store.modules = layout }
        }
        store.hidden = hidden
        for style in CelebrationStyle.allCases {
            await captureMotion(CelebrationView(count: 12, record: false, sample: true, style: style.rawValue).background(Theme.background),
                name: "particles-" + style.rawValue, directory: directory, width: 440, height: 340) { _ in }
        }
        verifyPreferences(directory: directory)
        await verifyReopening(directory: directory)
        if store.detectPushes { await verifyPushes(directory: directory) }
        try? "Complete\n".write(toFile: directory + "/review-complete.txt", atomically: true, encoding: .utf8)
    }

    private func verifyReopening(directory: String) async {
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        try? await Task.sleep(for: .milliseconds(250))
        store.settings = true
        try? await Task.sleep(for: .milliseconds(250))
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentViewController != nil && abs($0.contentViewController!.view.frame.width - Theme.width) < 2 }),
              let content = window.contentViewController?.view, let scroll = scrollViews(content).first else {
            assertionFailure("Couldn't find the real popover scroll view"); return
        }
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        let controller = window.contentViewController
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        try? await Task.sleep(for: .milliseconds(250))
        assert(!store.settings && window.contentViewController !== controller)
        assert(scrollViews(window.contentViewController!.view).allSatisfy { abs($0.contentView.bounds.minY) < 1 })
        await captureWindow(window, to: directory + "/reopened.png")
        while store.loading { try? await Task.sleep(for: .milliseconds(150)) }
        try? "PASS: real popover reopened from scrolled settings into a fresh dashboard controller at scroll origin zero.\n"
            .write(toFile: directory + "/reopening-check.txt", atomically: true, encoding: .utf8)
    }

    private var menuExamples: some View {
        VStack(spacing: 22) {
            sectionHeading("MENU BAR · SAMPLE DATA")
            ForEach(MenuStyle.allCases) { [self] style in
                HStack(spacing: 20) {
                    Text(style.title).font(.system(size: 10)).frame(width: 45, alignment: .leading)
                    ForEach([0, 12, 21], id: \.self) { count in
                        let history = (2..<28).map { ContributionDay(date: ContributionStats.offset(self.store.today, by: -$0), contributionCount: $0 * 3 % 11) }
                        let stats = ContributionStats(days: history + [ContributionDay(date: ContributionStats.offset(self.store.today, by: -1), contributionCount: 20),
                            ContributionDay(date: self.store.today, contributionCount: count)], today: self.store.today)
                        StatusLabel(stats: stats, connected: true, stale: false, showStreak: true, style: style.rawValue)
                    }
                }
            }
            HStack(spacing: 16) {
                StatusLabel(stats: nil, connected: false, stale: false, showStreak: false)
                StatusLabel(stats: store.stats, connected: true, stale: true, showStreak: false)
                RefreshButton(loading: true, action: {})
            }
        }.padding(22).frame(width: Theme.width).background(Theme.background)
    }

    private func verifyPreferences(directory: String) {
        let modules = store.modules, hidden = store.hidden, order = store.favouriteOrder
        defer { store.modules = modules; store.hidden = hidden; store.favouriteOrder = order }
        if let first = store.visibleModules.first, store.visibleModules.count > 1 {
            let second = store.visibleModules[1]
            store.moveModule(first, by: 1)
            assert(store.visibleModules[0] == second && store.visibleModules[1] == first)
            assert(UserDefaults.standard.stringArray(forKey: "modules") == store.modules.map(\.rawValue))
        }
        store.hidden.insert("today")
        assert(!store.visibleModules.contains(.today))
        store.hidden.remove("today")
        assert(store.visibleModules.contains(.today))
        let favourites = store.orderedPeople.filter { store.favourites.contains($0.login) }
        if favourites.count > 1 {
            store.moveFavourite(favourites[0].login, by: 1)
            assert(store.orderedPeople[0].login == favourites[1].login)
            assert(UserDefaults.standard.stringArray(forKey: "favouriteOrder") == store.favouriteOrder)
        }
        try? "PASS: widget movement, remove/add persistence, favourite ordering/persistence, and non-activating click-through celebration. Preferences restored.\n"
            .write(toFile: directory + "/ui-checks.txt", atomically: true, encoding: .utf8)
    }

    private func verifyPushes(directory: String) async {
        let root = URL(fileURLWithPath: directory).deletingLastPathComponent().appendingPathComponent("push-probe-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) -> Int32 {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
        }
        var results: [String] = []
        let remote = root.appendingPathComponent("remote.git").path
        assert(git(["init", "--bare", remote]) == 0)
        store.enablePushDetection(false)
        assert(!store.detectPushes && !FileManager.default.fileExists(atPath: PushMonitor.socketPath))
        assert(git(["config", "--global", "--fixed-value", "--get-all", "trace2.eventTarget", PushMonitor.target]) == 1)
        store.enablePushDetection(true)
        assert(store.detectPushes && FileManager.default.fileExists(atPath: PushMonitor.socketPath))
        assert(git(["config", "--global", "--fixed-value", "--get-all", "trace2.eventTarget", PushMonitor.target]) == 0)
        results.append("Disable/re-enable: own Git setting and socket removed, then restored successfully.")
        for index in 0..<2 {
            let repo = root.appendingPathComponent("repo\(index)").path
            assert(git(["init", repo]) == 0)
            let before = store.lastDetectedPush
            assert(git(["-C", repo, "-c", "user.name=Probe", "-c", "user.email=probe@example.invalid", "commit", "--allow-empty", "-m", "Probe"]) == 0)
            try? await Task.sleep(for: .milliseconds(350))
            assert(store.lastDetectedPush == before)
            assert(git(["-C", repo, "push", root.appendingPathComponent("missing.git").path, "HEAD"]) != 0)
            try? await Task.sleep(for: .milliseconds(350))
            assert(store.lastDetectedPush == before)
            let updatedBefore = store.dashboard?.updatedAt
            assert(git(["-C", repo, "push", remote, "HEAD:refs/heads/probe\(index)"]) == 0)
            for _ in 0..<80 {
                if store.lastDetectedPush != before && store.dashboard?.updatedAt != updatedBefore { break }
                try? await Task.sleep(for: .milliseconds(150))
            }
            assert(store.lastDetectedPush != before)
            assert(store.dashboard?.updatedAt != updatedBefore)
            results.append("Repo \(index): commit/failed push ignored; successful push detected; GitHub profile refreshed=\(store.dashboard?.updatedAt != updatedBefore)")
            let afterPush = store.lastDetectedPush
            assert(git(["-C", repo, "fetch", remote, "refs/heads/probe\(index)"]) == 0)
            try? await Task.sleep(for: .milliseconds(350))
            assert(store.lastDetectedPush == afterPush)
        }
        try? (results.joined(separator: "\n") + "\nNo GitHub writes. Disposable local remotes only.\n").write(toFile: directory + "/push-integration.txt", atomically: true, encoding: .utf8)
    }

    func captureReview(_ view: some View, to path: String, width: CGFloat = Theme.width, height: CGFloat = Theme.height, delay: Double = 0.8) async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window.center(); window.makeKeyAndOrderFront(nil)
        await captureWindow(window, to: path, delay: delay)
        window.close()
    }

    func captureWindow(_ window: NSWindow, to path: String, delay: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(delay))
        let marker = path + ".window"
        try? String(window.windowNumber).write(toFile: marker, atomically: true, encoding: .utf8)
        for _ in 0..<100 {
            if !FileManager.default.fileExists(atPath: marker) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func captureMotion(_ view: some View, name: String, directory: String, width: CGFloat = Theme.width, height: CGFloat = Theme.height, change: (Int) -> Void) async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window.center(); window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let marker = directory + "/" + name + ".motion"
        let signal = directory + "/" + name + ".start"
        try? String(window.windowNumber).write(toFile: marker, atomically: true, encoding: .utf8)
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: signal) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? FileManager.default.removeItem(atPath: signal)
        try? await Task.sleep(for: .milliseconds(400))
        change(6)
        try? await Task.sleep(for: .milliseconds(1300))
        change(24)
        for _ in 0..<300 {
            if !FileManager.default.fileExists(atPath: marker) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        window.close()
    }
}

@MainActor private final class ReviewFlipState: ObservableObject { @Published var flipped = false }
private struct ReviewFlipView: View {
    @ObservedObject var store: Store
    @ObservedObject var state: ReviewFlipState
    var body: some View {
        VStack(spacing: 0) {
            WidgetShell(module: .heatmap, store: store, configuring: state.flipped) { state.flipped.toggle() }
            ModuleContent(module: .streak, store: store)
            Spacer()
        }.padding(22).frame(width: Theme.width, height: Theme.height).background(Theme.background)
    }
}
#endif
