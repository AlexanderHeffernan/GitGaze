import AppKit
import Combine
import GitGlazeCore
import ServiceManagement
import UserNotifications

enum Module: String, Codable, CaseIterable, Identifiable {
    case today, streak, heatmap, favourites, momentum, records, people, years
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .streak: "Your streak"
        case .heatmap: "Contribution history"
        case .favourites: "Favourite people"
        case .momentum: "Weekly momentum"
        case .records: "Personal bests"
        case .people: "People you follow"
        case .years: "Year in perspective"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .streak: "flame"
        case .heatmap: "square.grid.3x3"
        case .favourites: "star"
        case .momentum: "chart.bar.xaxis"
        case .records: "trophy"
        case .people: "person.2"
        case .years: "chart.xyaxis.line"
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var dashboard: Dashboard?
    @Published var loading = false
    @Published var loadingHistory = false
    @Published var loadingPeople = false
    @Published var error: String?
    @Published var peopleError: String?
    @Published var settings = false
    @Published var modules: [Module] { didSet { persistPreferences() } }
    @Published var hidden: Set<String> { didSet { persistPreferences() } }
    @Published var favourites: Set<String> { didSet { persistPreferences() } }
    @Published var favouriteOrder: [String] { didSet { defaults.set(favouriteOrder, forKey: "favouriteOrder") } }
    @Published var palette: String { didSet { defaults.set(palette, forKey: "palette"); changed?() } }
    @Published var customLight: String { didSet { defaults.set(customLight, forKey: "customLight"); changed?() } }
    @Published var customDark: String { didSet { defaults.set(customDark, forKey: "customDark"); changed?() } }
    @Published var menuStyle: String { didSet { defaults.set(menuStyle, forKey: "menuStyle"); changed?() } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var notifications: Bool { didSet { defaults.set(notifications, forKey: "notifications") } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var peopleLimit = 12
    @Published var now = Date()
    @Published var celebration: (id: UUID, count: Int, record: Bool, sample: Bool)?
    @Published var visualCelebrations: Bool { didSet { defaults.set(visualCelebrations, forKey: "visualCelebrations") } }
    @Published var celebrationStyle: String { didSet { defaults.set(celebrationStyle, forKey: "celebrationStyle") } }
    @Published var reminder: Bool { didSet { defaults.set(reminder, forKey: "streakReminder") } }
    @Published var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    @Published private(set) var detectPushes: Bool
    @Published private(set) var lastDetectedPush: Date?
    private let pushMonitor = PushMonitor()
    private var activityTask: Task<Void, Never>?
    private var celebrationTask: Task<Void, Never>?
    private var increases = ContributionIncreaseTracker()
    var changed: (() -> Void)?
    private let defaults = UserDefaults.standard
    private var token: String?
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var session = UUID()
    private var lastHistoryRefresh: Date?
    private var lastPeopleRefresh: Date?

    var today: String { ContributionStats.dayKey(now) }
    var stats: ContributionStats? {
        dashboard.map { ContributionStats(days: $0.history + $0.profile.days, today: today) }
    }
    var visibleModules: [Module] { modules.filter { !hidden.contains($0.rawValue) } }
    var orderedPeople: [Person] {
        (dashboard?.following ?? []).sorted {
            if favourites.contains($0.login) != favourites.contains($1.login) { return favourites.contains($0.login) }
            if favourites.contains($0.login) {
                let a = favouriteOrder.firstIndex(of: $0.login) ?? Int.max
                let b = favouriteOrder.firstIndex(of: $1.login) ?? Int.max
                if a != b { return a < b }
            }
            return $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending
        }
    }
    var historyLabel: String {
        guard let dashboard else { return "GitHub history" }
        if !dashboard.historyComplete { return loadingHistory ? "Past year · loading history" : "Past year only" }
        return "Since \(dashboard.profile.years.min() ?? Calendar.current.component(.year, from: now))"
    }
    // Keep the pre-rename cache location so existing GitGlaze users retain offline history.
    var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitBar/dashboard.json")
    }

    init() {
        var savedModules = (defaults.stringArray(forKey: "modules") ?? []).compactMap(Module.init(rawValue:))
        for module in Module.allCases where !savedModules.contains(module) { savedModules.append(module) }
        modules = savedModules
        var savedHidden = Set(defaults.stringArray(forKey: "hidden") ?? ["momentum", "records", "people", "years"])
        if !(defaults.stringArray(forKey: "modules") ?? []).contains("years") { savedHidden.insert("years") }
        hidden = savedHidden
        favourites = Set(defaults.stringArray(forKey: "favourites") ?? [])
        favouriteOrder = defaults.stringArray(forKey: "favouriteOrder") ?? []
        palette = defaults.string(forKey: "palette") ?? "violet"
        customLight = defaults.string(forKey: "customLight") ?? "6E4AC9"
        customDark = defaults.string(forKey: "customDark") ?? "B09CFF"
        menuStyle = defaults.string(forKey: "menuStyle") ?? "charge"
        appearance = defaults.string(forKey: "appearance") ?? "system"
        notifications = defaults.bool(forKey: "notifications")
        visualCelebrations = defaults.object(forKey: "visualCelebrations") as? Bool ?? true
        celebrationStyle = defaults.string(forKey: "celebrationStyle") ?? "fireworks"
        reminder = defaults.bool(forKey: "streakReminder")
        reminderHour = defaults.object(forKey: "reminderHour") as? Int ?? 18
        detectPushes = defaults.bool(forKey: "detectPushes")
        if let data = try? Data(contentsOf: cacheURL) {
            dashboard = try? JSONDecoder().decode(Dashboard.self, from: data)
        }
        if let dashboard {
            let stats = ContributionStats(days: dashboard.profile.days, today: today)
            _ = increases.observe(day: today, count: stats.todayCount)
        }
        pushMonitor.onPush = { [weak self] in
            self?.lastDetectedPush = Date()
            self?.checkAfterLocalActivity()
        }
        if detectPushes {
            do { try pushMonitor.start() }
            catch { self.error = error.localizedDescription }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let oldDay = self.today
                self.now = Date()
                self.changed?()
                self.checkReminder()
                if oldDay != self.today || (self.dashboard?.updatedAt.timeIntervalSinceNow ?? -.infinity) < -300 {
                    self.refresh()
                }
            }
        }
    }

    func start() async {
        await useCLI()
        changed?()
    }

    func refresh(force: Bool = false) {
        now = Date()
        changed?()
        guard !loading else { return }
        if token == nil { refreshTask = Task { await useCLI() }; return }
        if !force, let date = dashboard?.updatedAt, Date().timeIntervalSince(date) < 30 { return }
        refreshTask = Task { await refreshNow() }
    }

    private func refreshNow(includeHistoryAndPeople: Bool = true) async {
        guard let token, !loading else { return }
        let generation = session
        loading = true
        error = nil
        defer { if session == generation { loading = false; changed?() } }
        let client = GitHubClient(token: token)
        do {
            let profile = try await client.viewer()
            guard session == generation, !Task.isCancelled else { return }
            now = Date()
            let previous = dashboard?.profile.person.login == profile.person.login ? dashboard : nil
            let oldCount = previous.map { ContributionStats(days: $0.profile.days, today: today).todayCount }
            dashboard = Dashboard(profile: profile, history: previous?.history ?? [],
                historyComplete: previous?.historyComplete ?? false, following: previous?.following ?? [],
                people: previous?.people ?? [:], updatedAt: Date())
            saveCache()
            changed?()
            let increase = increases.observe(day: today, count: stats?.todayCount ?? 0)
            if increase > 0, let stats {
                if visualCelebrations { showCelebration(count: increase, record: stats.isNewRecord) }
            }
            if increase > 0, let oldCount, let stats { celebrate(stats, oldCount: oldCount) }
            checkReminder()

            if includeHistoryAndPeople && (lastHistoryRefresh == nil || Date().timeIntervalSince(lastHistoryRefresh!) > 21_600) {
                loadingHistory = true
                do {
                    var history: [ContributionDay] = []
                    for year in profile.years.sorted() {
                        history += try await client.history(login: profile.person.login, year: year)
                        guard session == generation, !Task.isCancelled else { return }
                    }
                    dashboard?.history = ContributionStats(days: history, today: today).days
                    dashboard?.historyComplete = true
                    lastHistoryRefresh = Date()
                    saveCache()
                } catch {
                    if session == generation { self.error = "Full history couldn't refresh. \(error.localizedDescription)" }
                }
                loadingHistory = false
                changed?()
            }
            if includeHistoryAndPeople && (lastPeopleRefresh == nil || Date().timeIntervalSince(lastPeopleRefresh!) > 300) {
                do {
                    let following = try await client.following()
                    guard session == generation, !Task.isCancelled else { return }
                    dashboard?.following = following
                    lastPeopleRefresh = Date()
                    saveCache()
                    await loadPeople()
                } catch { if session == generation { peopleError = error.localizedDescription } }
            }
        } catch {
            if session == generation { self.error = error.localizedDescription }
        }
    }

    func loadPeople(logins: [String]? = nil) async {
        guard let token, !loadingPeople else { return }
        let generation = session
        let client = GitHubClient(token: token)
        loadingPeople = true
        peopleError = nil
        defer { if session == generation { loadingPeople = false } }
        // Only load the visible page and favourites, not every followed account.
        let visible = orderedPeople.prefix(peopleLimit)
        let wanted = Array(Set(logins ?? Array(visible.map(\.login))).union(favourites.intersection(Set(orderedPeople.map(\.login)))))
        for login in wanted {
            do {
                let profile = try await client.profile(login: login)
                guard session == generation, !Task.isCancelled else { return }
                dashboard?.people[login] = profile
            } catch { if session == generation { peopleError = error.localizedDescription } }
            guard session == generation, !Task.isCancelled else { return }
        }
        saveCache()
    }

    func toggleFavourite(_ login: String) {
        if favourites.contains(login) { favourites.remove(login) } else { favourites.insert(login) }
        if !favouriteOrder.contains(login) { favouriteOrder.append(login) }
        if favourites.contains(login), dashboard?.people[login] == nil {
            Task {
                while loadingPeople { try? await Task.sleep(for: .milliseconds(150)) }
                await loadPeople(logins: [login])
            }
        }
    }

    func moveFavourite(_ login: String, by offset: Int) {
        var order = orderedPeople.filter { favourites.contains($0.login) }.map(\.login)
        guard let index = order.firstIndex(of: login), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        favouriteOrder = order
    }

    func moveModule(_ module: Module, by offset: Int) {
        let visible = visibleModules
        guard let index = visible.firstIndex(of: module), visible.indices.contains(index + offset),
            let from = modules.firstIndex(of: module), let to = modules.firstIndex(of: visible[index + offset]) else { return }
        modules.swapAt(from, to)
    }

    func useCLI() async {
        guard let token = await Credentials.cliToken() else {
            error = "No GitHub CLI session found. Run gh auth login in Terminal, then try again."
            return
        }
        await connect(token)
    }

    private func connect(_ token: String) async {
        guard !loading else { return }
        let generation = session
        loading = true
        error = nil
        defer { if generation == session { loading = false } }
        do {
            // Validate the CLI identity before displaying another account's cache.
            let profile = try await GitHubClient(token: token).viewer()
            guard generation == session, !Task.isCancelled else { return }
            self.token = token
            if dashboard?.profile.person.login != profile.person.login {
                session = UUID()
                dashboard = nil
                increases = ContributionIncreaseTracker()
                clearCelebration()
                activityTask?.cancel()
                activityTask = nil
            }
            lastHistoryRefresh = nil
            lastPeopleRefresh = nil
            loading = false
            await refreshNow()
        } catch { if generation == session { self.error = error.localizedDescription } }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Couldn't change launch at login. \(error.localizedDescription)" }
    }

    func enableNotifications(_ enabled: Bool) {
        guard enabled else { notifications = false; return }
        Task {
            do { notifications = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { self.error = error.localizedDescription }
        }
    }

    func showCelebration(count: Int, record: Bool, sample: Bool = false) {
        celebrationTask?.cancel()
        celebration = (UUID(), count, record, sample)
        changed?()
        celebrationTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            celebration = nil
            changed?()
        }
    }

    private func clearCelebration() {
        celebrationTask?.cancel()
        celebration = nil
    }

    func enablePushDetection(_ enabled: Bool) {
        do {
            try pushMonitor.configure(enabled)
            detectPushes = enabled
            defaults.set(enabled, forKey: "detectPushes")
            if !enabled { activityTask?.cancel(); activityTask = nil }
        } catch { self.error = error.localizedDescription }
    }

    func checkAfterLocalActivity() {
        guard token != nil, activityTask == nil else { return }
        let generation = session
        activityTask = Task {
            defer {
                if session == generation { activityTask = nil }
            }
            // Check immediately, then allow time for GitHub's calendar to catch up.
            for delay in [0, 3, 7, 15, 30, 60, 90] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard session == generation else { return }
                if loading { continue }
                let before = stats?.todayCount ?? 0
                await refreshNow(includeHistoryAndPeople: false)
                if error != nil || (stats?.todayCount ?? 0) > before { return }
            }
        }
    }

    func enableReminder(_ enabled: Bool) {
        guard enabled else { reminder = false; return }
        Task {
            do { reminder = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func checkReminder() {
        guard reminder, token != nil, !loading, let dashboard, let stats,
            ContributionStats.dayKey(dashboard.updatedAt) == today,
            Date().timeIntervalSince(dashboard.updatedAt) < 600,
            stats.todayCount == 0, stats.currentStreak > 0,
            Calendar.current.component(.hour, from: now) >= reminderHour,
            defaults.string(forKey: "lastReminderDay") != today else { return }
        let content = UNMutableNotificationContent()
        content.title = "Keep your \(stats.currentStreak)-day streak going."
        content.body = "No contributions showing yet today. There's still time to make something."
        let day = today
        defaults.set(day, forKey: "lastReminderDay")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "streak-\(day)", content: content, trigger: nil)) { [weak self] error in
            if error != nil {
                Task { @MainActor in
                    self?.error = "The streak reminder couldn't be delivered. Check notification permissions in System Settings."
                }
            }
        }
    }

    private func celebrate(_ stats: ContributionStats, oldCount: Int) {
        guard notifications, oldCount == 0 || (stats.isNewRecord && oldCount <= stats.previousBest) else { return }
        let content = UNMutableNotificationContent()
        content.title = stats.isNewRecord ? "A new personal best!" : "You're on the board."
        content.body = stats.isNewRecord ? "\(stats.todayCount) contributions today. Look at you go." : "Your first contribution is in. Keep building something good."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "milestone-\(today)-\(stats.isNewRecord)", content: content, trigger: nil))
    }

    private func persistPreferences() {
        defaults.set(modules.map(\.rawValue), forKey: "modules")
        defaults.set(Array(hidden), forKey: "hidden")
        defaults.set(Array(favourites), forKey: "favourites")
    }

    private func saveCache() {
        guard let dashboard else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(dashboard).write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        } catch { self.error = "Couldn't save your offline cache. \(error.localizedDescription)" }
    }
}
