import AppKit
import SwiftUI
import Combine
import GitGazeCore

@main
struct GitGazeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = Store()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private var statusUpdateScheduled = false
    private var renderedStatus: StatusRender?
    private var flashing = false
    private(set) var celebrationPanel: NSPanel?
    private var displayedCelebration: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: Theme.width, height: Theme.height)
        // The dashboard is built when the popover opens and released when it closes, so a closed
        // popover never re-renders in the background on every store change.
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        let cursor = StatusCursorView(frame: button.bounds)
        cursor.autoresizingMask = [.width, .height]
        button.addSubview(cursor)
        store.changed = { [weak self] in self?.scheduleStatusUpdate() }
        cancellable = store.objectWillChange.sink { [weak self] in self?.scheduleStatusUpdate() }
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.scheduleStatusUpdate() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updateStatus()
        if CommandLine.arguments.contains("--smoke-test") {
            print("GitGaze launch smoke test passed")
            NSApp.terminate(nil)
            return
        }
        if !CommandLine.arguments.contains("--review") { store.updates.start() }
        Task {
            if CommandLine.arguments.contains("--enable-push-detection") { store.enablePushDetection(true) }
            await store.start()
            updateStatus()
            #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "--review"), CommandLine.arguments.count > index + 1 {
                await review(in: CommandLine.arguments[index + 1])
            }
            #endif
            if CommandLine.arguments.contains("--show") { showPopover() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func wake() { store.refresh() }
    @objc private func screensChanged() { scheduleStatusUpdate() }
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return true }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open GitGaze", action: #selector(showFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
            menu.addItem(.separator())
            let updates = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updates.isEnabled = store.updates.canCheck
            menu.autoenablesItems = false
            menu.addItem(withTitle: "Quit GitGaze", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 3), in: button) }
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc private func showFromMenu() { showPopover() }
    @objc private func refreshFromMenu() { store.refresh(force: true) }
    @objc private func checkForUpdates() { store.updates.check() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.settings = false
        // Each presentation owns its scroll position, expanded rows, searches and widget backs.
        popover.contentViewController = NSHostingController(rootView: DashboardView(store: store))
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Store changes arrive in bursts (objectWillChange fires before each property changes);
    /// collapse each burst into one status update after the values have settled.
    func scheduleStatusUpdate() {
        guard !statusUpdateScheduled else { return }
        statusUpdateScheduled = true
        Task { @MainActor [weak self] in self?.updateStatus() }
    }

    func updateStatus() {
        statusUpdateScheduled = false
        guard let button = statusItem?.button else { return }
        let label = StatusLabel(stats: store.stats, connected: store.dashboard != nil,
            stale: store.error != nil, showStreak: UserDefaults.standard.bool(forKey: "menuStreak"),
            celebrating: flashing, style: store.menuStyle)
        let appearance = button.effectiveAppearance
        let scale = max(button.window?.backingScaleFactor ?? 1, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        let render = StatusRender(label: label, dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            scale: scale, customLight: store.customLight, customDark: store.customDark)
        // The status item shows a pre-rendered image rather than a live NSHostingView. A live SwiftUI
        // view re-rendered whenever AppKit snapshotted it for another display's menu bar, and that
        // render dirtied the item again, so with multiple displays it redrew continuously.
        if render != renderedStatus, let image = render.image(appearance: appearance) {
            renderedStatus = render
            button.image = image
            statusItem.length = image.size.width + 12
        }
        let tooltip = store.dashboard == nil ? "GitGaze · Connect GitHub CLI" : "GitGaze · \(store.stats?.todayCount ?? 0) contributions today · \(store.stats?.currentStreak ?? 0)-day streak · \((MenuStyle(rawValue: store.menuStyle) ?? .charge).detail)"
        if button.toolTip != tooltip {
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
        }
        if let celebration = store.celebration, displayedCelebration != celebration.id {
            displayedCelebration = celebration.id
            flashStatus()
            presentCelebration(count: celebration.count, record: celebration.record, sample: celebration.sample)
        } else if store.celebration == nil {
            celebrationPanel?.orderOut(nil)
            celebrationPanel = nil
        }
    }

    /// A brief brighten of the menu-bar label when new work lands.
    private func flashStatus() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        flashing = true
        scheduleStatusUpdate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.flashing = false
            self?.scheduleStatusUpdate()
        }
    }

    private func presentCelebration(count: Int, record: Bool, sample: Bool) {
        guard let button = statusItem?.button, let window = button.window, let screen = window.screen else { return }
        celebrationPanel?.orderOut(nil)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let size = NSSize(width: 440, height: reduceMotion ? 90 : 340)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(visible.minX + 6, anchor.midX - size.width / 2), visible.maxX - size.width - 6)
        let y = max(visible.minY + 6, anchor.minY - size.height - 6)
        panel.contentViewController = NSHostingController(rootView: CelebrationView(count: count, record: record, sample: sample, anchorX: anchor.midX - x, style: store.celebrationStyle))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        celebrationPanel = panel
        panel.orderFrontRegardless()
    }
}

/// Keeps the pointing-hand cursor over the status item without intercepting clicks.
final class StatusCursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func isAccessibilityElement() -> Bool { false }
}

/// Everything that affects the menu-bar pixels. Rendering is skipped when none of it changed.
struct StatusRender: Equatable {
    let label: StatusLabel
    let dark: Bool
    let scale: CGFloat
    let customLight: String
    let customDark: String

    @MainActor func image(appearance: NSAppearance) -> NSImage? {
        let renderer = ImageRenderer(content: label.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = scale
        var image: NSImage?
        // Resolve the palette's dynamic NSColors against the menu bar, not the app's appearance.
        appearance.performAsCurrentDrawingAppearance { image = renderer.nsImage }
        return image
    }
}

enum MenuStyle: String, CaseIterable, Identifiable {
    case orbit, charge, pulse, mosaic, prism, ribbon
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .orbit, .charge, .prism: "Progress toward next daily best"
        case .pulse: "Last seven days of activity"
        case .mosaic: "Last four weeks of activity"
        case .ribbon: "Last seven active days"
        }
    }
}

/// Just the figures the menu-bar label draws, so two labels can be compared cheaply.
struct StatusFigures: Equatable {
    let todayCount: Int
    let currentStreak: Int
    let progress: Double
    let isNewRecord: Bool
    /// The last 28 days, oldest first.
    let recent: [Int]

    init(_ stats: ContributionStats) {
        todayCount = stats.todayCount
        currentStreak = stats.currentStreak
        progress = stats.progress
        isNewRecord = stats.isNewRecord
        recent = (0..<28).map { stats.count(on: ContributionStats.offset(stats.today, by: $0 - 27)) }
    }
}

struct StatusLabel: View, Equatable {
    let stats: StatusFigures?
    let connected: Bool
    let stale: Bool
    let showStreak: Bool
    var celebrating = false
    var style = "charge"
    var palette = Theme.palette

    init(stats: ContributionStats?, connected: Bool, stale: Bool, showStreak: Bool, celebrating: Bool = false, style: String = "charge") {
        self.stats = stats.map(StatusFigures.init)
        self.connected = connected
        self.stale = stale
        self.showStreak = showStreak
        self.celebrating = celebrating
        self.style = style
    }

    private var count: String { connected ? String(stats?.todayCount ?? 0) : "–" }
    var body: some View {
        HStack(spacing: 5) {
            if style == "charge" {
                HStack(spacing: 5) {
                    Text(count).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    if showStreak, let stats {
                        Rectangle().fill(.primary.opacity(0.22)).frame(width: 0.5, height: 9)
                        Text("\(stats.currentStreak)d").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 11).frame(height: 19)
                    .background(palette.color.opacity(0.08), in: ChargeOutline())
                    .overlay(ChargeOutline().stroke(palette.color.opacity(0.55), lineWidth: 0.8))
                    .overlay(alignment: .bottomLeading) {
                        GeometryReader { geometry in
                            Capsule().fill(stats?.isNewRecord == true ? Theme.gold : palette.color)
                                .frame(width: max(0, (geometry.size.width - 18) * (stats?.progress ?? 0)), height: 1.5).offset(x: 7, y: 17)
                        }.allowsHitTesting(false)
                    }
            } else if style == "ribbon" {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(count).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        if showStreak, let stats { Text("\(stats.currentStreak)d").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                    MiniActivity(stats: stats, style: style, color: palette.color).frame(width: showStreak ? 38 : 25, height: 3)
                }
            } else {
                if style == "orbit" {
                    RecordDial(progress: stats?.progress ?? 0, active: (stats?.todayCount ?? 0) > 0, record: stats?.isNewRecord == true).frame(width: 19, height: 19)
                } else { MiniActivity(stats: stats, style: style, color: palette.color).frame(width: style == "pulse" ? 29 : style == "mosaic" ? 12 : 20, height: 19) }
                Text(count).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                if showStreak, let stats {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(palette.color)
                        Text("\(stats.currentStreak)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                    }.padding(.leading, 1)
                }
            }
            if stale { Circle().fill(Theme.gold).frame(width: 3, height: 3) }
        }.frame(height: 22).fixedSize().allowsHitTesting(false).accessibilityHidden(true)
            .brightness(celebrating ? 0.25 : 0)
    }
}

private struct MiniActivity: View {
    let stats: StatusFigures?
    let style: String
    let color: Color
    var body: some View {
        let days = style == "mosaic" ? 28 : 7
        let values = Array((stats?.recent ?? Array(repeating: 0, count: 28)).suffix(days))
        Canvas { context, size in
            let accent = stats?.isNewRecord == true ? Theme.gold : color
            if style == "prism" {
                let points = [CGPoint(x: size.width / 2, y: 0), CGPoint(x: size.width, y: size.height / 2), CGPoint(x: size.width / 2, y: size.height), CGPoint(x: 0, y: size.height / 2)]
                for index in 0..<4 {
                    var face = Path(); face.move(to: CGPoint(x: size.width / 2, y: size.height / 2)); face.addLine(to: points[index]); face.addLine(to: points[(index + 1) % 4]); face.closeSubpath()
                    let lit = (stats?.todayCount ?? 0) > 0 && Double(index) / 4 < (stats?.progress ?? 0)
                    context.fill(face, with: .color(lit ? accent.opacity(1 - Double(index) * 0.16) : .primary.opacity(0.18 + Double(index) * 0.05)))
                }
            } else if style == "pulse" {
                let maximum = Double(max(1, values.max() ?? 0))
                var line = Path()
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: Double(index) / 6 * size.width, y: 16 - Double(value) / maximum * 12)
                    if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                context.stroke(line, with: .color(accent.opacity(0.18)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            } else {
                for (index, value) in values.enumerated() {
                    let rect: CGRect
                    if style == "mosaic" { rect = CGRect(x: Double(index / 7) * 3, y: Double(index % 7) * 2.6, width: 2, height: 1.8) }
                    else { rect = CGRect(x: CGFloat(index) * size.width / 7, y: 0, width: size.width / 7 - 1, height: 3) }
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.6), with: .color(value > 0 ? accent.opacity(0.4 + min(0.6, Double(value) / 20)) : .primary.opacity(0.22)))
                }
            }
        }
    }
}
