#if DEBUG
import AppKit
import CoreFoundation
import GitGazeCore
import WebKit

struct FlyoutFixture: Decodable {
    let today: String
    let dashboard: Dashboard
}

/// Opt-in host for the shared renderer; fixture comparisons have no native service access.
@MainActor final class FlyoutReview: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let mode: String
    let root: URL
    let fixture: FlyoutFixture
    private var snapshot: [String: Any]
    private var close: (() -> Void)?
    weak var view: WKWebView?
    private var liveController: NSViewController?
    private let local: SharedMacLocal?

    init(mode: String, local: SharedMacLocal? = nil) throws {
        self.mode = mode
        self.local = local
        root = Bundle.main.resourceURL!.appendingPathComponent("SharedClient", isDirectory: true)
        let bytes = try Data(contentsOf: root.appendingPathComponent("fixture.json"))
        fixture = try JSONDecoder().decode(FlyoutFixture.self, from: bytes)
        snapshot = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    }

    func controller(close: @escaping () -> Void) -> NSViewController {
        self.close = close
        if let liveController {
            view?.evaluateJavaScript("window.gitGazeOpen?.()", completionHandler: nil)
            return liveController
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "gitgaze")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: Theme.width, height: Theme.height), configuration: configuration)
        web.navigationDelegate = self
        web.appearance = NSAppearance(named: .aqua)
        view = web
        let controller = NSViewController()
        controller.view = web
        if local != nil { liveController = controller }
        web.loadFileURL(root.appendingPathComponent("dashboard.html"), allowingReadAccessTo: root)
        return controller
    }

    private func isDashboard(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return url.standardizedFileURL.path == root.appendingPathComponent("dashboard.html").standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        isDashboard(navigationAction.request.url) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        FileHandle.standardError.write(Data("WebKit navigation: \(error.localizedDescription)\n".utf8))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === view,
              isDashboard(view?.url),
              let state = message.body as? [String: Any], let action = state["action"] as? String else { return }
        switch action {
        case "ready":
            if local == nil {
                view?.callAsyncJavaScript("window.gitGazeReceive(snapshot)", arguments: ["snapshot": snapshot], in: nil, in: .page, completionHandler: nil)
            } else { view?.evaluateJavaScript("window.gitGazeStart()", completionHandler: nil) }
        case "preferences":
            snapshot["preferences"] = state["value"]
        case "request":
            guard let local, let call = state["value"] as? [String: Any], let id = call["id"] as? Int, id > 0, id <= Int(Int32.max),
                  call["version"] as? Int == 1, let method = call["method"] as? String,
                  let bytes = try? JSONSerialization.data(withJSONObject: call), bytes.count <= 4_000_000 else { return }
            let args = call["args"]
            Task { @MainActor in
                let reply: [String: Any]
                do { reply = ["id": id, "result": try await local.request(method, args: args)] }
                catch { reply = ["id": id, "error": error.localizedDescription, "code": (error as? GitHubError)?.code ?? "unknown"] }
                view?.callAsyncJavaScript("window.gitGazeReply(reply)", arguments: ["reply": reply], in: nil, in: .page, completionHandler: nil)
            }
        case "dismiss": close?()
        default: break
        }
    }

    func evaluate(_ source: String) async throws -> Any? {
        try await view?.evaluateJavaScript(source)
    }

    func capture(_ controller: NSViewController, to path: String) async throws {
        let image: NSBitmapImageRep?
        if let web = controller.view as? WKWebView {
            let snapshot = try await web.takeSnapshot(configuration: nil)
            image = snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        } else {
            let view = controller.view
            view.layoutSubtreeIfNeeded()
            image = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            if let image { view.cacheDisplay(in: view.bounds, to: image) }
        }
        guard let bytes = image?.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

@MainActor final class SharedMacLocal {
    let cache: URL
    let defaults: UserDefaults
    let credentials: Bool
    var reviewResponse: (@MainActor (String, [String: Any]) async throws -> Any)?
    private var token: String?

    init(cache: URL, defaults: UserDefaults, credentials: Bool = true) {
        self.cache = cache
        self.defaults = defaults
        self.credentials = credentials
    }

    private static let keys = ["modules", "hidden", "favourites", "favouriteOrder", "palette", "customLight", "customDark", "menuStyle", "menuStreak",
        "appearance", "notifications", "visualCelebrations", "celebrationStyle", "streakReminder", "reminderHour", "lastReminderDay", "detectPushes", "historyWeeks", "comparisonYear", "comparisonMode", "leaderboardOrganization"]
    private static func login(_ value: Any?) -> Bool {
        (value as? String)?.wholeMatch(of: /[A-Za-z0-9-]{1,39}/) != nil
    }
    private static func nodeID(_ value: Any?) -> Bool {
        (value as? String)?.wholeMatch(of: /[A-Za-z0-9_+=\/-]{1,256}/) != nil
    }
    private static func leaderboardVariables(_ operation: String, _ values: [String: Any]) -> Bool {
        guard operation == "leaderboardOrganizations" || operation == "leaderboardMembers" else { return true }
        guard values["after"] is NSNull || (1...1024).contains((values["after"] as? String)?.utf8.count ?? 0) else { return false }
        if operation == "leaderboardOrganizations" { return true }
        let format = ISO8601DateFormatter(); format.formatOptions.insert(.withFractionalSeconds)
        guard login(values["login"]), nodeID(values["org"]),
              let from = values["from"] as? String, let to = values["to"] as? String,
              let start = format.date(from: from), let end = format.date(from: to) else { return false }
        return abs(end.timeIntervalSince(start) - 30 * 86_400) < 0.001
    }
    private static func valid(_ key: String, _ value: Any) -> Bool {
        switch key {
        case "leaderboardOrganization":
            guard let pair = value as? [String: Any], pair.count == 2 else { return false }
            return login(pair["account"]) && nodeID(pair["id"])
        case "appearance": return ["system", "light", "dark"].contains(value as? String ?? "")
        case "historyWeeks": return [26, 53].contains(value as? Int ?? 0)
        case "reminderHour":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let hour = value as? Int else { return false }
            return (0...23).contains(hour)
        case "modules", "hidden":
            guard let list = value as? [String], list.count <= 32 else { return false }
            return Set(list).count == list.count && list.allSatisfy { id in
                id.wholeMatch(of: /[a-z][a-z0-9-]{0,31}/) != nil
            }
        default: return false
        }
    }

    func request(_ method: String, args: Any?) async throws -> Any {
        switch method {
        case "readLocal":
            let prefs = defaults.dictionaryRepresentation().filter { Self.keys.contains($0.key) }
            let data = try? Data(contentsOf: cache)
            // Bad/older cache is treated as missing, not sent into the renderer.
            let dashboard = data.flatMap { bytes in
                (try? JSONDecoder().decode(Dashboard.self, from: bytes)) == nil ? nil : try? JSONSerialization.jsonObject(with: bytes)
            }
            return ["preferences": prefs, "dashboard": dashboard ?? NSNull()]
        case "writePreferences":
            guard let prefs = args as? [String: Any], prefs.allSatisfy({ Self.valid($0.key, $0.value) }) else { throw CocoaError(.validationMissingMandatoryProperty) }
            for (key, value) in prefs {
                defaults.set(value, forKey: key)
            }
        case "writeCache":
            guard let args, JSONSerialization.isValidJSONObject(args) else { throw CocoaError(.fileWriteUnknown) }
            let bytes = try JSONSerialization.data(withJSONObject: args)
            _ = try JSONDecoder().decode(Dashboard.self, from: bytes)
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try bytes.write(to: cache, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        case "github":
            guard let input = args as? [String: Any], let operation = input["operation"] as? String,
                  let required = ["viewer": [], "following": ["after"], "profile": ["login"], "history": ["login", "from", "to"],
                                  "leaderboardOrganizations": ["after"], "leaderboardMembers": ["login", "org", "from", "to", "after"]][operation],
                  let values = input["variables"] as? [String: Any], Set(values.keys) == Set(required),
                  values.allSatisfy({ ($0.key == "after" && $0.value is NSNull) || (($0.value as? String)?.utf8.count ?? 1025) <= 1024 }),
                  Self.leaderboardVariables(operation, values),
                  let manifest = Bundle.main.url(forResource: "operations", withExtension: "json", subdirectory: "SharedClient"),
                  let query = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))[operation] else {
                throw GitHubError.message("Unsupported GitHub request.")
            }
            if let reviewResponse, !credentials { return try await reviewResponse(operation, values) }
            if operation == "viewer" { token = credentials ? await Credentials.cliToken() : nil }
            guard let token else {
                throw GitHubError.classified("No GitHub CLI session found. Run gh auth login --hostname github.com, then try again.", code: "access")
            }
            let data = try await GitHubClient(token: token).query(query, variables: values.compactMapValues { $0 as? String })
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = envelope["data"] else {
                throw GitHubError.message("GitHub did not return activity data.")
            }
            return result
        default: throw GitHubError.message("Unsupported host request.")
        }
        return NSNull()
    }
}

extension AppDelegate {
    private func verifyLeaderboardFlyout(output: String) async throws {
        let suite = "app.gitbar.mac.leaderboard-review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cache = URL(fileURLWithPath: output).appendingPathComponent("\(UUID().uuidString)/dashboard.json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let local = SharedMacLocal(cache: cache, defaults: defaults, credentials: false)
        defaults.set(["today"], forKey: "modules")
        defaults.set(["streak", "heatmap", "favourites", "momentum", "records", "people", "years"], forKey: "hidden")
        defaults.set(26, forKey: "historyWeeks")
        let login = "calendar-fixture"
        var failure: String?
        var queries = 0
        local.reviewResponse = { operation, vars in
            let last: [String: Any] = ["hasNextPage": false, "endCursor": NSNull()]
            switch operation {
            case "viewer": return ["viewer": ["login": login, "name": "Jamie", "avatarUrl": "", "contributionsCollection": [
                "contributionYears": [], "restrictedContributionsCount": 0, "contributionCalendar": ["totalContributions": 0, "weeks": []]]]]
            case "following": return ["viewer": ["following": ["nodes": [], "pageInfo": last]]]
            case "leaderboardOrganizations":
                queries += 1
                return ["viewer": ["login": login, "organizations": ["pageInfo": last, "nodes": [
                    ["id": "north", "login": "northstar-labs", "viewerIsAMember": true],
                    ["id": "south", "login": "tideline-studio", "viewerIsAMember": true]]]]]
            case "leaderboardMembers":
                try await Task.sleep(for: .milliseconds(350))
                if let failure, failure != "roster_limit" { throw GitHubError.classified("Fixture failure", code: failure) }
                let north = vars["org"] as? String == "north"
                let handles = north ? ["Amira", "Ben", "Cora", "Dev", "Eli", "Flo", login, "Haru"] : ["Amira", login]
                let counts = north ? [72, 56, 56, 38, 29, 24, 19, 8] : [0, 0]
                let rows: [[String: Any]] = zip(handles, counts).map { handle, count in
                    ["login": handle, "name": handle == login ? "Jamie Reed" : handle, "avatarUrl": "", "contributionsCollection": [
                        "totalCommitContributions": count, "totalIssueContributions": 0, "totalPullRequestContributions": 0, "totalPullRequestReviewContributions": 0]]
                }
                return ["viewer": ["login": login], "organization": ["id": north ? "north" : "south", "viewerIsAMember": true,
                    "membersWithRole": ["totalCount": failure == "roster_limit" ? 501 : rows.count, "nodes": rows, "pageInfo": last]]]
            default: throw GitHubError.message("Unexpected fixture operation")
            }
        }
        let review = try FlyoutReview(mode: "shared", local: local)
        flyoutReview = review
        reviewPopover.animates = false
        NSApp.activate(ignoringOtherApps: true)
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        func wait(_ expression: String) async throws {
            for _ in 0..<40 {
                if (try? await review.evaluate(expression)) as? Bool == true { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw GitHubError.message("Leaderboard review failed: \(expression)")
        }
        func click(_ label: String) async throws {
            _ = try await review.evaluate("document.querySelector('[aria-label=\"\(label)\"]').click(); void 0")
        }
        func capture(_ name: String) async throws {
            guard let controller = reviewPopover.contentViewController else { throw CocoaError(.fileWriteUnknown) }
            _ = try await review.evaluate("document.querySelector('[data-widget=leaderboard]').scrollIntoView(); void 0")
            try await Task.sleep(for: .milliseconds(600))
            try await review.capture(controller, to: output + "/leaderboard-\(name).png")
        }
        try await wait("!!document.querySelector('[data-widget=today]') && document.querySelector('#account').textContent === '@calendar-fixture'")
        try await wait("!document.querySelector('[data-widget=leaderboard]')")
        guard queries == 0 else { throw GitHubError.message("Hidden widget queried GitHub") }
        try await click("Add widgets")
        try await capture("gallery")
        try await click("Add Organization leaderboard")
        try await click("Back to dashboard")
        try await wait("document.querySelector('.leaderboard-rank')?.textContent === '#7 of 8 visible members'")
        try await capture("ranked")
        try await click("Show more ranked members")
        try await wait("document.querySelectorAll('.leaderboard-rows li').length === 8 && !!document.querySelector('.leaderboard-you')")
        failure = "network"
        try await click("Refresh leaderboard")
        try await wait("!!document.querySelector('.leaderboard-rank') && document.querySelector('.leaderboard-status').textContent.includes('Refreshing leaderboard')")
        try await wait("!!document.querySelector('.leaderboard-rank') && document.querySelector('.leaderboard-status').textContent.includes('last complete ranking')")
        try await capture("stale")
        failure = "access"
        try await click("Retry leaderboard")
        try await wait("!document.querySelector('.leaderboard-rank') && document.querySelector('.leaderboard-status').textContent.includes('SSO')")
        try await click("Configure Organization leaderboard")
        try await wait("!!document.querySelector('[data-widget=leaderboard] select') && !!document.querySelector('[aria-label=\"Recheck leaderboard access\"]') && !document.querySelector('[aria-label=\"Retry leaderboard\"]')")
        try await capture("access-settings")
        failure = "roster_limit"
        try await click("Recheck leaderboard access")
        try await wait("document.querySelector('.leaderboard-status').textContent.includes('500 visible members') && !!document.querySelector('[data-widget=leaderboard] select') && !document.querySelector('.leaderboard-status button')")
        try await capture("roster-limit")
        failure = nil
        _ = try await review.evaluate("const selector=document.querySelector('[data-widget=leaderboard] select'); selector.value='south'; selector.dispatchEvent(new Event('change')); void 0")
        try await wait("document.querySelector('.leaderboard-rank')?.textContent === '#1 of 2 visible members' && document.querySelectorAll('.leaderboard-rows li').length === 2 && document.querySelector('.leaderboard-org')?.textContent === 'tideline-studio'")
        try await capture("switched")
        guard defaults.dictionary(forKey: "leaderboardOrganization")?["id"] as? String == "south",
              defaults.integer(forKey: "historyWeeks") == 26, defaults.stringArray(forKey: "hidden")?.contains("leaderboard") == false else {
            throw GitHubError.message("Leaderboard preferences were not persisted without drift")
        }
        try "WKWebView fixture: opt-in from legacy layout, scoped rank #7/8, expansion, refresh/stale, access clearing + picker, roster limit, switch to tied zeroes, local preferences saved without changing history setting. No GitHub requests.\n"
            .write(toFile: output + "/leaderboard-check.txt", atomically: true, encoding: .utf8)
    }

    func compareFlyout(mode: String, output: String) async {
        func require(_ success: Bool, _ reason: String) throws {
            if !success { throw NSError(domain: "Flyout review", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(500)) }
        var facts: [String] = []
        do {
            if mode == "leaderboard" {
                try await verifyLeaderboardFlyout(output: output)
                NSApp.terminate(nil)
                return
            }
            if mode == "migration" {
                let directory = URL(fileURLWithPath: output).appendingPathComponent(UUID().uuidString)
                let suite = "app.gitbar.mac.review.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
                let cache = directory.appendingPathComponent("GitBar/dashboard.json")
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                let fixture = try FlyoutReview(mode: "shared").fixture
                let legacy = try JSONEncoder().encode(fixture.dashboard)
                try legacy.write(to: cache)
                defaults.set(53, forKey: "historyWeeks")
                defaults.set("violet", forKey: "palette")
                let local = SharedMacLocal(cache: cache, defaults: defaults, credentials: false)
                let review = try FlyoutReview(mode: "shared", local: local)
                flyoutReview = review
                reviewPopover.animates = false
                NSApp.activate(ignoringOtherApps: true)
                await settle()
                _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                for _ in 0..<30 {
                    if (try? await review.evaluate("document.querySelector('#status').textContent")) as? String == "Cached activity · refresh failed" { break }
                    try? await Task.sleep(for: .milliseconds(150))
                }
                let state = try await review.evaluate("[document.querySelector('#status').textContent, document.querySelector('#account').textContent, document.querySelector('.heat')?.getAttribute('aria-label')].join('|')") as? String
                try require(state == "Cached activity · refresh failed|@\(fixture.dashboard.profile.person.login)|53-week contribution graph", "Legacy cache did not load offline: \(state ?? "nil")")
                _ = try await review.evaluate("document.querySelector('[aria-label=\"Configure Contribution history\"]').click();const field=document.activeElement;field.value='26';field.dispatchEvent(new Event('change'));void 0")
                await settle()
                let focused = try await review.evaluate("document.activeElement.getAttribute('aria-label')") as? String
                try require(focused == "Configure Contribution history", "Selection must restore focus")
                try require(UserDefaults(suiteName: suite)?.integer(forKey: "historyWeeks") == 26 && defaults.string(forKey: "palette") == "violet", "Preference patch did not persist or clobbered legacy state")
                let bytes = try Data(contentsOf: cache)
                try require(bytes == legacy, "Offline refresh modified the legacy cache")
                try "WKWebView loaded Swift Codable disk cache offline, saved 26 weeks to disposable defaults without replacing palette or cache, and restored selector focus.\n".write(toFile: output + "/migration-check.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            try require(["shared", "reference"].contains(mode), "Unknown mode: \(mode)")
            let review = try FlyoutReview(mode: mode)
            flyoutReview = review
            reviewPopover.animates = false
            NSApp.appearance = NSAppearance(named: .aqua)
            store.loadFlyoutFixture(review.fixture)
            guard let stats = store.stats else { throw CocoaError(.fileReadCorruptFile) }
            let values = [stats.todayCount, stats.currentStreak, stats.previousBest, stats.bestWeek, stats.weekTotal, stats.lastWeekTotal, stats.monthTotal, stats.yearTotal]
            try require(values == [7, 5, 12, 23, 7, 23, 17, 33], "Swift cache fixture metrics not as expected: \(values)")
            facts.append("Swift Codable decode and Swift core figures: \(values)")
            updateStatus()
            for _ in 0..<12 {
                if reviewStatusButton?.window != nil { break }
                try? await Task.sleep(for: .milliseconds(150))
            }
            NSApp.activate(ignoringOtherApps: true)
            await settle()
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            await settle()
            guard let controller = reviewPopover.contentViewController, let window = controller.view.window else {
                try require(false, "Cannot find popover window (shown=\(reviewPopover.isShown), screens=\(NSScreen.screens.count))")
                return
            }
            guard let button = reviewStatusButton, let statusWindow = button.window else {
                try require(false, "Cannot find the status item's AppKit window")
                return
            }
            let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
            try require(reviewPopover.isShown && reviewPopover.behavior == .transient && window.isKeyWindow, "Popover must be transient, shown and keyboard-active")
            try require(window.frame.maxX >= anchor.minX && window.frame.minX <= anchor.maxX && window.frame.minY < anchor.minY,
                        "Popover must position against the status item")
            facts.append("\(mode): anchored transient key popover; status \(anchor), popover \(window.frame)")
            if mode == "shared" {
                for _ in 0..<16 {
                    if (try? await review.evaluate("document.querySelector('.number')?.textContent || ''")) as? String == "7" { break }
                    try? await Task.sleep(for: .milliseconds(125))
                }
                let count = try await review.evaluate("document.querySelector('.number')?.textContent || ''") as? String
                let debug = try await review.evaluate("[location.href, document.readyState, typeof gitGazeCore, typeof gitGazeReceive, !!window.webkit?.messageHandlers.gitgaze].join('|')")
                try require(count == "7", "Shared page did not render fixture count: \(String(describing: count)); page \(String(describing: debug))")
            }
            try await review.capture(controller, to: output + "/\(mode)-flyout.png")
            if mode == "shared" {
                let gallery = try await review.evaluate("document.querySelector('[aria-label=\"Add widgets\"]').click();[...document.querySelectorAll('.week-day')].map(day=>day.firstChild.textContent).join(',')+'|'+[...document.querySelectorAll('.best-number')].map(n=>n.textContent).join(',')") as? String
                try require(gallery == "7,0,0,0,0,0,0|12,23,5", "Gallery must render Monday-first contributions and personal bests: \(gallery ?? "nil")")
                await settle()
                try await review.capture(controller, to: output + "/shared-gallery.png")
                _ = try await review.evaluate("document.querySelector('[aria-label=\"Back to dashboard\"]').click();void 0")
                let focused = try await review.evaluate("document.querySelector('[aria-label=\"Configure Contribution history\"]').click();document.activeElement.tagName") as? String
                try require(focused == "SELECT", "Widget back should move focus into its native-styled selector")
                await settle()
                try await review.capture(controller, to: output + "/shared-widget-settings.png")
                let restored = try await review.evaluate("const input=document.activeElement;input.value='26';input.dispatchEvent(new Event('change'));document.activeElement.getAttribute('aria-label')") as? String
                try require(restored == "Configure Contribution history", "Selection must restore focus")
                await settle()
                try await review.capture(controller, to: output + "/shared-six-months.png")
                _ = try await review.evaluate("document.activeElement.click();document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));void 0")
                let escaped = try await review.evaluate("document.activeElement.getAttribute('aria-label')") as? String
                try require(escaped == "Configure Contribution history", "Escape must restore focus")
                _ = try await review.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));void 0")
            } else {
                store.settings = true
                await settle()
                reviewPopover.close()
            }
            for _ in 0..<20 {
                if !reviewPopover.isShown && reviewPopover.contentViewController == nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try require(!reviewPopover.isShown, "Popover should close")
            try require(reviewPopover.contentViewController == nil, "Popover should release its presentation")
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            await settle()
            try require(reviewPopover.isShown && reviewPopover.contentViewController !== controller, "Reopen should allocate a fresh presentation")
            if mode == "shared" {
                let state = try await review.evaluate("[document.querySelector('h1').textContent,document.querySelector('main').scrollTop,document.querySelector('.heat')?.getAttribute('aria-label')].join('|')") as? String
                try require(state == "GitGaze|0|26-week contribution graph", "Shared reopen should reset navigation while keeping preference: \(String(describing: state))")
                facts.append("Shared WebKit: heading/fixture figure rendered; widget back focused SELECT; Escape closed host; reopen reset page and scroll while retaining 26-week setting (in-memory review bridge)")
            } else {
                // Reference controller is recreated on every presentation; don't write real preferences.
                store.settings = false
                facts.append("SwiftUI reference: native close released controller and reopen created another")
            }
            try (facts.joined(separator: "\n") + "\n").write(toFile: output + "/\(mode)-check.txt", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("\(mode): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
#endif
