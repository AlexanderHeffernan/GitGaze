import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns download verification, safe replacement, authorisation, and relaunch.
/// Never run a downloaded installer script or reuse the GitHub CLI token for updates.
@MainActor
final class AppUpdates: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    @Published private(set) var automatic = false

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automatic)
    }

    func start() { controller.startUpdater() }
    func setAutomatic(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func check() {
        guard canCheck else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

struct UpdateSettings: View {
    @ObservedObject var updates: AppUpdates
    var body: some View {
        Card {
            HStack {
                sectionHeading("UPDATES")
                Spacer()
                Text(updates.version).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Toggle("Check automatically", isOn: Binding(get: { updates.automatic }, set: { updates.setAutomatic($0) }))
            HStack {
                Text("Verified updates, installed in place.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Check now") { updates.check() }.buttonStyle(QuietButtonStyle()).disabled(!updates.canCheck)
            }
        }
    }
}
