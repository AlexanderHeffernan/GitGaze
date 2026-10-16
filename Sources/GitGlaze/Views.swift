import SwiftUI
import GitGlazeCore

struct DashboardView: View {
    @ObservedObject var store: Store
    @State var widgetSettings: Module?
    @State var adding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            DashboardScroll {
                VStack(spacing: 0) {
                    if let error = store.error { message(error, symbol: "wifi.exclamationmark") }
                    if store.settings { SettingsView(store: store) }
                    else if adding { WidgetGallery(store: store) }
                    else if store.dashboard != nil {
                        ForEach(store.visibleModules) { module in
                            WidgetShell(module: module, store: store, configuring: widgetSettings == module) {
                                widgetSettings = widgetSettings == module ? nil : module
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                        if store.visibleModules.isEmpty {
                            Button { adding = true } label: { Label("Add a widget", systemImage: "plus") }
                                .buttonStyle(QuietButtonStyle()).padding(.vertical, 50)
                        }
                    } else if store.loading {
                        ProgressView("Syncing activity…").controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 100)
                    } else { WelcomeView(store: store) }
                }.padding(.horizontal, 22)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.48, bounce: 0.1), value: store.visibleModules)
            }.id(store.settings ? "settings" : adding ? "gallery" : "dashboard")
            Divider().opacity(0.4)
            footer
        }
        .frame(width: Theme.width, height: Theme.height).background(Theme.background).id(store.palette)
        .tint(Theme.accent)
        .preferredColorScheme(store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(store.settings ? "Settings" : adding ? "Add widgets" : "GitGlaze").font(.system(size: 14, weight: .semibold)).tracking(-0.3)
            Spacer()
            if store.settings || adding {
                Button { store.settings = false; adding = false } label: {
                    Label("Back", systemImage: "arrow.turn.up.left").font(.system(size: 11, weight: .medium))
                }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
            } else {
                IconButton(symbol: "plus", label: "Add widgets") { adding = true }
                RefreshButton(loading: store.loading) { store.refresh(force: true) }
                IconButton(symbol: "slider.horizontal.3", label: "Settings") { store.settings = true }
            }
        }.padding(.horizontal, 20).padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.error != nil ? Theme.gold : Theme.accent).frame(width: 4, height: 4)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let seconds = Int(context.date.timeIntervalSince(store.dashboard?.updatedAt ?? context.date))
                Text(store.loading ? "Refreshing…" : store.dashboard == nil ? "Not connected" : seconds < 60 ? "Updated now" : seconds < 3600 ? "Updated \(seconds / 60)m ago" : "Updated \(seconds / 3600)h ago")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            if let login = store.dashboard?.profile.person.login {
                Link("@\(login)", destination: URL(string: "https://github.com/\(login)")!)
                    .font(.system(size: 9)).buttonStyle(QuietButtonStyle())
            }
        }.padding(.horizontal, 22).padding(.vertical, 7)
    }
}

/// Live widget content is reused by the dashboard and the add gallery, not separate mock previews.
struct ModuleContent: View {
    let module: Module
    @ObservedObject var store: Store
    var body: some View {
        if let stats = store.stats, let dashboard = store.dashboard {
            switch module {
            case .today: TodayCard(stats: stats, historyLabel: store.historyLabel, historyComplete: dashboard.historyComplete)
            case .streak: StreakCard(stats: stats)
            case .heatmap: HistoryCard(profile: dashboard.profile, today: store.today)
            case .favourites: PeopleCard(store: store, favouritesOnly: true)
            case .people: PeopleCard(store: store, favouritesOnly: false)
            case .momentum: MomentumCard(stats: stats, days: dashboard.profile.days, today: store.today)
            case .records: RecordsCard(stats: stats)
            case .years: YearComparisonCard(store: store)
            }
        }
    }
}

struct WidgetGallery: View {
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            if store.hidden.isEmpty { Text("All widgets added").font(.system(size: 12)).foregroundStyle(.secondary).padding(30) }
            ForEach(store.modules.filter { store.hidden.contains($0.rawValue) }) { module in
                Button { store.hidden.remove(module.rawValue) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(module.title).font(.system(size: 11, weight: .medium))
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
                        }.padding(.top, 14)
                        ModuleContent(module: module, store: store)
                            .fixedSize(horizontal: false, vertical: true).frame(maxHeight: 205, alignment: .top).clipped()
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }.padding(.horizontal, 14).padding(.bottom, 4)
                        .background(Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.075)))
                }.buttonStyle(TileButtonStyle()).accessibilityLabel("Add \(module.title)")
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }.padding(.vertical, 16).animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.05), value: store.hidden)
    }
}

struct WidgetShell: View {
    let module: Module
    @ObservedObject var store: Store
    let configuring: Bool
    let configure: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var configurable: Bool { [.favourites, .people, .streak, .heatmap, .years].contains(module) }
    var body: some View {
        FlippingWidget(flipped: configuring) {
            ModuleContent(module: module, store: store).overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    IconButton(symbol: "arrow.up", label: "Move \(module.title) up") { store.moveModule(module, by: -1) }
                        .disabled(store.visibleModules.first == module)
                    IconButton(symbol: "arrow.down", label: "Move \(module.title) down") { store.moveModule(module, by: 1) }
                        .disabled(store.visibleModules.last == module)
                    if configurable { IconButton(symbol: "slider.horizontal.3", label: "Configure \(module.title)", action: configure) }
                    IconButton(symbol: "minus.circle", label: "Remove \(module.title)") { store.hidden.insert(module.rawValue) }
                }.background(Theme.background, in: RoundedRectangle(cornerRadius: 7)).padding(.top, 4)
                    .opacity(hovered ? 1 : 0).allowsHitTesting(hovered)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
            }
        } back: {
            Card {
                HStack {
                    sectionHeading(module.title.uppercased())
                    Spacer()
                    Button(action: configure) { Label("Back", systemImage: "arrow.uturn.backward").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(QuietButtonStyle())
                }
                switch module {
                case .favourites, .people: PeopleSettings(store: store)
                case .streak:
                    Toggle("Streak reminder", isOn: Binding(get: { store.reminder }, set: { store.enableReminder($0) }))
                    if store.reminder {
                        ChoiceMenu(title: "When today is empty after", selection: $store.reminderHour,
                            options: (0..<24).map { ($0, String(format: "%02d:00", $0)) })
                    }
                case .heatmap: HistoryOptions()
                case .years: YearComparisonOptions(store: store)
                default: EmptyView()
                }
            }.font(.system(size: 11)).toggleStyle(TrailingSwitchStyle()).controlSize(.small)
                .background(Theme.background)
        }.onHover { hovered = $0 }
    }
}

struct WelcomeView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RecordDial(progress: 0.65, active: true).frame(width: 64, height: 64).padding(.top, 35)
            Text("Your work, in view.").font(.system(size: 28, weight: .medium)).tracking(-1)
            Text("Connect with your GitHub CLI session.").font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                if Credentials.cliPath == nil { command("brew install gh") }
                command("gh auth login")
            }
            Button { Task { await store.useCLI() } } label: {
                HStack { Text("Connect GitHub CLI"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.system(size: 12, weight: .medium)).padding(13)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.25)))
            }.buttonStyle(TileButtonStyle()).disabled(store.loading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
    }
    private func command(_ text: String) -> some View {
        Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
