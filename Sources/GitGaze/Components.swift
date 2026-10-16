import SwiftUI

enum Palette: String, CaseIterable, Identifiable {
    case violet, coral, ice, graphite, mint, rose, amber, cobalt, orchid, lagoon, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color { Color(nsColor: nsColor) }
    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if self == .custom {
                return Theme.color(hex: UserDefaults.standard.string(forKey: dark ? "customDark" : "customLight") ?? (dark ? "B09CFF" : "6E4AC9")) ?? .systemPurple
            }
            let rgb: (CGFloat, CGFloat, CGFloat) = switch self {
            case .violet: dark ? (0.69, 0.61, 1) : (0.43, 0.29, 0.79)
            case .coral: dark ? (1, 0.57, 0.49) : (0.77, 0.25, 0.21)
            case .ice: dark ? (0.42, 0.81, 0.97) : (0.06, 0.43, 0.64)
            case .graphite: dark ? (0.83, 0.85, 0.91) : (0.29, 0.33, 0.42)
            case .mint: dark ? (0.46, 0.86, 0.73) : (0.08, 0.47, 0.36)
            case .rose: dark ? (1, 0.56, 0.74) : (0.75, 0.19, 0.43)
            case .amber: dark ? (1, 0.75, 0.35) : (0.64, 0.36, 0.03)
            case .cobalt: dark ? (0.46, 0.63, 1) : (0.18, 0.36, 0.83)
            case .orchid: dark ? (0.86, 0.56, 1) : (0.59, 0.23, 0.75)
            case .lagoon: dark ? (0.30, 0.85, 0.86) : (0.04, 0.45, 0.48)
            case .custom: (0, 0, 0) // Resolved above for the current appearance.
            }
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }
}

enum Theme {
    static func color(hex: String) -> NSColor? {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static var palette: Palette { Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "violet") ?? .violet }
    static var accent: Color { palette.color }
    static let gold = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.78, blue: 0.44, alpha: 1)
            : NSColor(red: 0.65, green: 0.36, blue: 0.08, alpha: 1)
    })
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.085, green: 0.087, blue: 0.11, alpha: 1)
            : NSColor(red: 0.975, green: 0.973, blue: 0.986, alpha: 1)
    })
    static let width: CGFloat = 384
    static let height: CGFloat = 640
}

/// One interaction treatment for every quiet action, including widget and person controls.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? (hovered ? Theme.accent : Color.primary.opacity(0.65)) : Color.primary.opacity(0.25))
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : hovered && enabled ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovered = $0 }
            .handCursor(enabled)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

struct TileButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(enabled && hovered ? 0.035 : 0)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(enabled && hovered ? 0.14 : 0), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
            .handCursor(enabled)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}

struct TrailingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 10)
            Toggle(isOn: configuration.$isOn) { configuration.label }.labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.padding(.vertical, 2).handCursor()
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 14, height: 14) }
            .buttonStyle(QuietButtonStyle()).help(label).accessibilityLabel(label)
    }
}

/// Shared, app-styled selection surfaces. The menu itself retains native keyboard navigation.
struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                ForEach(options.indices, id: \.self) { index in
                    Button { selection = options[index].0 } label: {
                        if selection == options[index].0 { Label(options[index].1, systemImage: "checkmark") }
                        else { Text(options[index].1) }
                    }
                }
            } label: {
                Text(options.first { $0.0 == selection }?.1 ?? options.first?.1 ?? "")
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                .padding(.leading, 11).padding(.trailing, 26).padding(.vertical, 8)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.18)))
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.accent).padding(.trailing, 9).allowsHitTesting(false)
                }.handCursor().accessibilityLabel(title)
        }.font(.system(size: 11))
    }
}

struct ChoiceStrip<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button { selection = option.0 } label: {
                        Text(option.1).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selection == option.0 ? Theme.accent : Color.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background {
                                if selection == option.0 {
                                    RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.12)).matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }.contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(TileButtonStyle()).accessibilityAddTraits(selection == option.0 ? .isSelected : [])
                }
            }.padding(3).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
        }.accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct RefreshButton: View {
    let loading: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !loading || reduceMotion)) { context in
            Button(action: action) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(loading && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360 : 0))
                    .font(.system(size: 12, weight: .medium)).frame(width: 14, height: 14)
            }.buttonStyle(QuietButtonStyle()).disabled(loading)
        }.help(loading ? "Refreshing…" : "Refresh").accessibilityLabel(loading ? "Refreshing contributions" : "Refresh contributions")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
    }
}

func sectionHeading(_ title: String) -> some View {
    Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
}

func message(_ text: String, symbol: String) -> some View {
    Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(Theme.gold)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).padding(.top, 10)
}

extension View {
    func handCursor(_ enabled: Bool = true) -> some View { background(HandCursor(enabled: enabled)) }
}

private struct HandCursor: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> CursorRegion { CursorRegion() }
    func updateNSView(_ view: CursorRegion, context: Context) {
        view.enabled = enabled
        view.window?.invalidateCursorRects(for: view)
    }
    final class CursorRegion: NSView {
        var enabled = true
        override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .pointingHand) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Both faces keep their own state; only the facing side is interactive or exposed to accessibility.
struct FlippingWidget<Front: View, Back: View>: View {
    let flipped: Bool
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heights: [Int: CGFloat] = [:]
    var body: some View {
        Group {
            if reduceMotion {
                if flipped { back.transition(.opacity) } else { front.transition(.opacity) }
            } else {
                ZStack(alignment: .top) {
                    face(front, index: 0).modifier(FlipFace(angle: flipped ? 180 : 0))
                        .allowsHitTesting(!flipped).accessibilityHidden(flipped)
                    face(back, index: 1).modifier(FlipFace(angle: flipped ? 0 : -180))
                        .allowsHitTesting(flipped).accessibilityHidden(!flipped)
                }.frame(height: heights[flipped ? 1 : 0], alignment: .top)
                    .onPreferenceChange(FaceHeights.self) { heights = $0 }
            }
        }.animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.55, bounce: 0.08), value: flipped)
    }
    private func face(_ view: some View, index: Int) -> some View {
        view.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: FaceHeights.self, value: [index: geometry.size.height])
            })
    }
}

private struct FaceHeights: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct FlipFace: AnimatableModifier {
    nonisolated var angle: Double
    nonisolated var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        content.opacity(abs(angle) < 90 ? 1 : 0)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// Native scrolling and draggable scrollbar, with a quieter themed knob even under Always Show Scrollbars.
struct DashboardScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { content.background(ScrollChrome()) }
    }
}

private struct ScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollAnchor { ScrollAnchor() }
    func updateNSView(_ view: ScrollAnchor, context: Context) { view.styleScrollView() }
}

private final class ScrollAnchor: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); styleScrollView() }
    func styleScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let scroll = self?.enclosingScrollView else { return }
            if !(scroll.verticalScroller is AccentScroller) { scroll.verticalScroller = AccentScroller() }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.verticalScroller?.needsDisplay = true
        }
    }
}

private final class AccentScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let knob = rect(for: .knob)
        let slim = NSRect(x: knob.midX - 1.5, y: knob.minY, width: 3, height: knob.height)
        Theme.palette.nsColor.withAlphaComponent(hitPart == .knob ? 0.8 : 0.38).setFill()
        NSBezierPath(roundedRect: slim, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
