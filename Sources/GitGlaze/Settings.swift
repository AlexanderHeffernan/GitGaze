import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @AppStorage("menuStreak") private var menuStreak = false
    @State private var confirmDetection = false
    var body: some View {
        VStack(spacing: 0) {
            Card {
                sectionHeading("APPEARANCE")
                HStack(spacing: 8) {
                    appearance("system", "Auto", "circle.lefthalf.filled")
                    appearance("light", "Light", "sun.max")
                    appearance("dark", "Dark", "moon")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(Palette.allCases.filter { $0 != .custom }) { palette in
                        Button { store.palette = palette.rawValue } label: {
                            VStack(spacing: 3) {
                                Circle().fill(palette.color.gradient).frame(width: 22, height: 22)
                                    .overlay { if store.palette == palette.rawValue { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.background) } }
                                    .padding(3).overlay(Circle().strokeBorder(store.palette == palette.rawValue ? palette.color.opacity(0.7) : .clear, lineWidth: 1))
                                Text(palette.title).font(.system(size: 8)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(TileButtonStyle()).help(palette.title).accessibilityLabel("\(palette.title) theme")
                            .accessibilityAddTraits(store.palette == palette.rawValue ? .isSelected : [])
                    }
                }.padding(.top, 3)
                HStack {
                    Button { store.palette = "custom" } label: {
                        Label("Custom theme", systemImage: store.palette == "custom" ? "checkmark.circle.fill" : "paintpalette")
                            .foregroundStyle(store.palette == "custom" ? Theme.accent : Color.secondary)
                    }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Circle().fill(Palette.custom.color).frame(width: 13, height: 13)
                }
                if store.palette == "custom" {
                    HStack(spacing: 10) {
                        ThemeColorField(title: "Light accent", hex: $store.customLight)
                        ThemeColorField(title: "Dark accent", hex: $store.customDark)
                    }
                }
            }
            Card {
                sectionHeading("MENU BAR")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(MenuStyle.allCases) { style in menuOption(style.rawValue, style.title) }
                }
                Toggle("Show streak", isOn: $menuStreak).onChange(of: menuStreak) { store.changed?() }
            }
            Card {
                sectionHeading("CELEBRATIONS")
                Toggle("Visual celebrations", isOn: $store.visualCelebrations)
                HStack(spacing: 7) {
                    ForEach(CelebrationStyle.allCases) { style in
                        Button {
                            store.celebrationStyle = style.rawValue
                            store.showCelebration(count: 3, record: false, sample: true)
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: style.symbol).font(.system(size: 19, weight: .light)).foregroundStyle(Theme.accent)
                                Text(style.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(Theme.accent.opacity(store.celebrationStyle == style.rawValue ? 0.1 : 0.025), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.celebrationStyle == style.rawValue ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.07)))
                        }.buttonStyle(TileButtonStyle()).accessibilityAddTraits(store.celebrationStyle == style.rawValue ? .isSelected : [])
                    }
                }
                Toggle("Milestone notifications", isOn: Binding(get: { store.notifications }, set: { store.enableNotifications($0) }))
            }
            Card {
                sectionHeading("GENERAL")
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.toggleLaunchAtLogin($0) }))
                Toggle("Detect pushes automatically", isOn: Binding(get: { store.detectPushes }, set: { enabled in
                    if enabled { confirmDetection = true } else { store.enablePushDetection(false) }
                }))
                .confirmationDialog("Enable push detection across repositories?", isPresented: $confirmDetection) {
                    Button("Enable Git integration") { store.enablePushDetection(true) }
                } message: {
                    Text("Adds Git's trace2.eventTarget setting to your user configuration. Events stay on this Mac, in memory. Turning this off removes only GitGlaze's setting. Clients that bypass Git aren't covered.")
                }
            }
            if let person = store.dashboard?.profile.person {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: person.avatarUrl)) { image in image.resizable() } placeholder: { Circle().fill(.quaternary) }
                        .frame(width: 28, height: 28).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName).font(.system(size: 11, weight: .medium))
                        Text("@\(person.login)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("GitHub CLI").font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(.vertical, 15)
            }
        }.font(.system(size: 11)).toggleStyle(TrailingSwitchStyle()).controlSize(.mini)
    }

    private func appearance(_ value: String, _ title: String, _ symbol: String) -> some View {
        Button { store.appearance = value } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5).fill(value == "dark" ? Color(white: 0.14) : Color(white: 0.96))
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Theme.accent).frame(width: 18, height: 3)
                        Capsule().fill(Color.gray.opacity(0.25)).frame(width: 33, height: 2)
                        Capsule().fill(Color.gray.opacity(0.15)).frame(width: 23, height: 2)
                    }.padding(9)
                    if value == "system" { UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5).fill(Color.black.opacity(0.55)).frame(width: 27).frame(maxWidth: .infinity, alignment: .trailing) }
                }.frame(width: 55, height: 40)
                Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(store.appearance == value ? Theme.accent.opacity(0.09) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.appearance == value ? Theme.accent.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: 1))
        }.buttonStyle(TileButtonStyle()).help("\(title) appearance").accessibilityAddTraits(store.appearance == value ? .isSelected : [])
    }

    private func menuOption(_ value: String, _ title: String) -> some View {
        Button { store.menuStyle = value } label: {
            VStack(spacing: 8) {
                StatusLabel(stats: store.stats, connected: store.dashboard != nil, stale: false, showStreak: true, style: value)
                    .frame(height: 24)
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(store.menuStyle == value ? Theme.accent.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.menuStyle == value ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.07), lineWidth: 1))
        }.buttonStyle(TileButtonStyle()).help("\(title) menu bar display").accessibilityAddTraits(store.menuStyle == value ? .isSelected : [])
    }
}

private struct ThemeColorField: View {
    let title: String
    @Binding var hex: String
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ColorPicker(title, selection: Binding(get: { Color(nsColor: Theme.color(hex: hex) ?? .systemPurple) }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                }), supportsOpacity: false).labelsHidden().fixedSize().handCursor()
                Text("#").foregroundStyle(.secondary)
                TextField("RRGGBB", text: $draft).textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                    .onChange(of: draft) { _, value in
                        if Theme.color(hex: value) != nil { hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased() }
                    }
                    .accessibilityLabel(title + " hex colour")
            }.padding(8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(!draft.isEmpty && Theme.color(hex: draft) == nil ? Theme.gold : Color.primary.opacity(0.08)))
        }.frame(maxWidth: .infinity).onAppear { draft = hex }.onChange(of: hex) { _, value in if draft.uppercased() != value { draft = value } }
    }
}
