#if DEBUG
import AppKit
import GitGazeCore
import WebKit

struct FlyoutFixture: Decodable {
    let today: String
    let dashboard: Dashboard
}

/// Experiment only: same signed bundle's local resources, no network, credentials or real preferences.
@MainActor final class FlyoutReview: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let mode: String
    let root: URL
    let fixture: FlyoutFixture
    private var snapshot: [String: Any]
    private var close: (() -> Void)?
    weak var view: WKWebView?

    init(mode: String) throws {
        self.mode = mode
        root = Bundle.main.resourceURL!.appendingPathComponent("SharedClient", isDirectory: true)
        let bytes = try Data(contentsOf: root.appendingPathComponent("fixture.json"))
        fixture = try JSONDecoder().decode(FlyoutFixture.self, from: bytes)
        snapshot = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    }

    func controller(close: @escaping () -> Void) -> NSViewController {
        self.close = close
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "gitgaze")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: Theme.width, height: Theme.height), configuration: configuration)
        web.navigationDelegate = self
        web.appearance = NSAppearance(named: .aqua)
        view = web
        let controller = NSViewController()
        controller.view = web
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
            view?.callAsyncJavaScript("window.gitGazeReceive(snapshot)", arguments: ["snapshot": snapshot], in: nil, in: .page, completionHandler: nil)
        case "preferences":
            snapshot["preferences"] = state["value"]
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

extension AppDelegate {
    func compareFlyout(mode: String, output: String) async {
        func require(_ success: Bool, _ reason: String) throws {
            if !success { throw NSError(domain: "Flyout review", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(500)) }
        var facts: [String] = []
        do {
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
                let focused = try await review.evaluate("document.querySelector('[aria-label=\"Configure Contribution history\"]').click();document.activeElement.tagName") as? String
                try require(focused == "SELECT", "Widget back should move focus into its native-styled selector")
                await settle()
                try await review.capture(controller, to: output + "/shared-widget-settings.png")
                _ = try await review.evaluate("const input=document.activeElement;input.value='26';input.dispatchEvent(new Event('change'));document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));void 0")
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
