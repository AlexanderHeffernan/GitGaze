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
    private var started = ContinuousClock.now
    private(set) var phases: [String] = []
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
        started = .now
        phases = []
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
        phases.append("load submitted: \(started.duration(to: .now))")
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
            phases.append("bridge ready: \(started.duration(to: .now))")
            if local == nil {
                view?.callAsyncJavaScript("const start = performance.now(); window.gitGazeReceive(snapshot); return performance.now() - start;", arguments: ["snapshot": snapshot], in: nil, in: .page) { [weak self, started] result in
                    guard let self, self.started == started, let elapsed = try? result.get() else { return }
                    self.phases.append("fixture rendered: \(started.duration(to: .now)); JS receive/render: \(elapsed) ms")
                }
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
    private var token: String?

    init(cache: URL, defaults: UserDefaults, credentials: Bool = true) {
        self.cache = cache
        self.defaults = defaults
        self.credentials = credentials
    }

    private static let keys = ["modules", "hidden", "favourites", "favouriteOrder", "palette", "customLight", "customDark", "menuStyle", "menuStreak",
        "appearance", "notifications", "visualCelebrations", "celebrationStyle", "streakReminder", "reminderHour", "lastReminderDay", "detectPushes", "historyWeeks", "comparisonYear", "comparisonMode"]
    private static func valid(_ key: String, _ value: Any) -> Bool {
        switch key {
        case "appearance": return ["system", "light", "dark"].contains(value as? String ?? "")
        case "palette": return Palette(rawValue: value as? String ?? "") != nil
        case "customLight", "customDark": return (value as? String)?.wholeMatch(of: /[0-9A-Fa-f]{6}/) != nil
        case "historyWeeks": return [26, 53].contains(value as? Int ?? 0)
        case "comparisonMode": return ["ytd", "full"].contains(value as? String ?? "")
        case "favourites", "favouriteOrder":
            guard let logins = value as? [String], logins.count <= 10_000, Set(logins).count == logins.count else { return false }
            return logins.allSatisfy { $0.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9-]{0,38}/) != nil }
        case "comparisonYear":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let year = value as? Int else { return false }
            return year == 0 || (2008...9999).contains(year)
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
                  let required = ["viewer": [], "following": ["after"], "profile": ["login"], "history": ["login", "from", "to"]][operation],
                  let values = input["variables"] as? [String: Any], Set(values.keys) == Set(required),
                  values.allSatisfy({ ($0.key == "after" && $0.value is NSNull) || (($0.value as? String)?.utf8.count ?? 1025) <= 1024 }),
                  let manifest = Bundle.main.url(forResource: "operations", withExtension: "json", subdirectory: "SharedClient"),
                  let query = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))[operation] else {
                throw GitHubError.message("Unsupported GitHub request.")
            }
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
    func compareFlyout(mode: String, output: String) async {
        func require(_ success: Bool, _ reason: String) throws {
            if !success { throw NSError(domain: "Flyout review", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(500)) }
        var facts: [String] = []
        do {
            if ["migration", "migration-seed", "migration-upgrade", "migration-relaunch"].contains(mode) {
                let disposable = mode == "migration"
                let directory = URL(fileURLWithPath: output).appendingPathComponent(disposable ? UUID().uuidString : "upgrade-state")
                let suite = "app.gitbar.mac.review.\(directory.path.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) })"
                let defaults = UserDefaults(suiteName: suite)!
                defer {
                    if disposable || mode == "migration-relaunch" {
                        defaults.removePersistentDomain(forName: suite)
                        try? FileManager.default.removeItem(at: directory)
                    }
                }
                let cache = directory.appendingPathComponent("GitBar/dashboard.json")
                let fixture = try FlyoutReview(mode: "shared").fixture
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
                let stamp = directory.appendingPathComponent("version")
                if disposable || mode == "migration-seed" {
                    try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(fixture.dashboard).write(to: cache)
                    defaults.set(53, forKey: "historyWeeks")
                    defaults.set("violet", forKey: "palette")
                    defaults.set(true, forKey: "detectPushes")
                    try version.write(to: stamp, atomically: true, encoding: .utf8)
                    if mode == "migration-seed" {
                        try "Version \(version) seeded disposable Swift Codable cache and preferences.\n".write(toFile: output + "/\(mode)-check.txt", atomically: true, encoding: .utf8)
                        NSApp.terminate(nil)
                        return
                    }
                }
                let legacy = try Data(contentsOf: cache)
                if !disposable {
                    let installed = try String(contentsOf: stamp, encoding: .utf8)
                    try require(installed != version, "Replacement must report a different bundle version")
                }
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
                let weeks = mode == "migration-relaunch" ? 26 : 53
                try require(state == "Cached activity · refresh failed|@\(fixture.dashboard.profile.person.login)|\(weeks)-week contribution graph", "Legacy cache did not load offline: \(state ?? "nil")")
                if mode != "migration-relaunch" {
                    _ = try await review.evaluate("document.querySelector('[aria-label=\"Configure Contribution history\"]').click();const field=document.activeElement;field.value='26';field.dispatchEvent(new Event('change'));void 0")
                    await settle()
                    let focused = try await review.evaluate("document.activeElement.getAttribute('aria-label')") as? String
                    try require(focused == "Configure Contribution history", "Selection must restore focus")
                }
                try require(defaults.integer(forKey: "historyWeeks") == 26 && defaults.string(forKey: "palette") == "violet" && defaults.bool(forKey: "detectPushes"), "Preference patch did not persist or clobbered legacy state")
                let bytes = try Data(contentsOf: cache)
                try require(bytes == legacy, "Offline refresh modified the legacy cache")
                try "Version \(version): WKWebView opened offline with \(weeks) weeks; 26 weeks persisted without changing palette, Git push detection preference, or cache.\n".write(toFile: output + "/\(mode)-check.txt", atomically: true, encoding: .utf8)
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
            let opening = ContinuousClock.now
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            if mode == "shared" {
                for _ in 0..<80 {
                    if (try? await review.evaluate("document.querySelector('.number')?.textContent || ''")) as? String == "7" { break }
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }
            if let content = reviewPopover.contentViewController?.view {
                content.layoutSubtreeIfNeeded()
                content.window?.displayIfNeeded()
            }
            facts.append("\(mode): programmatic open to laid-out content \(opening.duration(to: .now)) (animation off; not input-to-screen)")
            await settle()
            if mode == "shared" { facts.append("cold WebKit: " + review.phases.joined(separator: "; ")) }
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
                        "Popover must position against the status item: window \(window.frame), anchor \(anchor)")
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
                let years = try await review.evaluate("""
                    document.querySelector('[aria-label="Add Year in perspective"]').click();
                    document.querySelector('[aria-label="Back to dashboard"]').click();
                    const card = () => document.querySelector('[data-widget="years"]');
                    const summary = () => card().querySelector('.year-delta').textContent + '|' + card().querySelector('svg').getAttribute('aria-label');
                    const ytd = summary();
                    card().querySelector('[aria-label="Configure Year in perspective"]').click();
                    const field = card().querySelector('[aria-label="Period"]');
                    field.focus(); field.value = 'full'; field.dispatchEvent(new Event('change'));
                    const retained = document.activeElement.getAttribute('aria-label');
                    card().querySelector('[aria-label="Back from Year in perspective"]').click();
                    ytd + '|' + retained + '|' + summary()
                    """) as? String
                let olderYTD = stats.total(inYear: 2023, throughMonthDay: "03-04")
                let olderFull = stats.total(inYear: 2023, throughMonthDay: "12-31")
                try require(olderYTD == 11 && olderFull == 44, "Unexpected Swift year fixture totals")
                try require(years == "+22|2024 and 2023 cumulative contributions, same point in each year|Period|−11|2024 and 2023 cumulative contributions, full years", "Year comparison fixture: \(years ?? "nil")")
                _ = try await review.evaluate("document.querySelector('[data-widget=years]').scrollIntoView();void 0")
                await settle()
                try await review.capture(controller, to: output + "/shared-year-full.png")
                _ = try await review.evaluate("document.querySelector('[aria-label=\"Remove Year in perspective\"]').click();document.querySelector('main').scrollTop=0;void 0")
                let focused = try await review.evaluate("document.querySelector('[aria-label=\"Configure Contribution history\"]').click();document.activeElement.tagName") as? String
                try require(focused == "SELECT", "Widget back should move focus into its native-styled selector")
                await settle()
                try await review.capture(controller, to: output + "/shared-widget-settings.png")
                let restored = try await review.evaluate("const input=document.activeElement;input.value='26';input.dispatchEvent(new Event('change'));document.activeElement.getAttribute('aria-label')") as? String
                try require(restored == "Configure Contribution history", "Selection must restore focus")
                await settle()
                try await review.capture(controller, to: output + "/shared-six-months.png")
                let people = try await review.evaluate("""
                    const configure = () => document.querySelector('[aria-label="Configure Favourite people"]').click();
                    configure();
                    const search = document.activeElement;
                    search.value = 'no-match'; search.dispatchEvent(new Event('input'));
                    const empty = document.querySelector('.people-list').textContent;
                    search.value = 'MIRA'; search.dispatchEvent(new Event('input'));
                    document.querySelector('[aria-label="Unfavourite mira-fixture"]').click();
                    const available = !!document.querySelector('[aria-label="Favourite mira-fixture"]');
                    document.querySelector('[aria-label="Favourite mira-fixture"]').click();
                    empty + '|' + available + '|' + !!document.querySelector('[aria-label="Unfavourite mira-fixture"]')
                    """) as? String
                try require(people == "No matching people|true|true", "Favourites search and toggle: \(people ?? "nil")")
                await settle()
                try await review.capture(controller, to: output + "/shared-people-settings.png")
                let theme = try await review.evaluate("""
                    document.querySelector('[aria-label="Settings"]').click();
                    document.querySelector('[aria-label="Custom theme"]').click();
                    const color = document.querySelector('[aria-label="Light accent"]');
                    color.value = '#236b8e'; color.dispatchEvent(new Event('change'));
                    getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()
                    """) as? String
                try require(theme == "#236B8E", "Custom accent did not render: \(theme ?? "nil")")
                await settle()
                try await review.capture(controller, to: output + "/shared-appearance.png")
                _ = try await review.evaluate("document.querySelector('[aria-label=\"Violet theme\"]').click();document.querySelector('[aria-label=\"Back to dashboard\"]').click();document.querySelector('[aria-label=\"Configure Contribution history\"]').focus();void 0")
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
            let reopening = ContinuousClock.now
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            if mode == "shared" {
                for _ in 0..<80 {
                    if (try? await review.evaluate("document.querySelector('.number')?.textContent")) as? String == "7" { break }
                    try? await Task.sleep(for: .milliseconds(25))
                }
                facts.append("warm process, recreated WKWebView: \(reopening.duration(to: .now)); " + review.phases.joined(separator: "; "))
            }
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
