import SwiftUI
import GitGazeCore

@MainActor
final class OrganizationLeaderboard: ObservableObject {
    @Published private(set) var organizations: [GitHubOrganization]?
    @Published private(set) var selectedID = ""
    @Published private(set) var rows: [OrganizationStanding]?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private(set) var login = ""
    private var discover: (() async throws -> [GitHubOrganization])?
    private var standings: ((GitHubOrganization) async throws -> [OrganizationStanding])?
    private var task: Task<Void, Never>?
    private var lastAttempt: Date?
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var organization: GitHubOrganization? { organizations?.first { $0.id == selectedID } }
    private var preferenceKey: String { "leaderboardOrganization.\(login.lowercased())" }

    func connect(login: String, discover: @escaping () async throws -> [GitHubOrganization],
                 standings: @escaping (GitHubOrganization) async throws -> [OrganizationStanding]) {
        cancel()
        self.login = login
        self.discover = discover
        self.standings = standings
        selectedID = defaults.string(forKey: preferenceKey) ?? ""
        organizations = nil
        rows = nil
        error = nil
        lastAttempt = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        if loading { lastAttempt = nil }
        loading = false
    }

    func select(_ id: String) {
        guard selectedID != id, organizations?.contains(where: { $0.id == id }) == true else { return }
        cancel()
        selectedID = id
        defaults.set(id, forKey: preferenceKey)
        load(force: true, rediscover: false)
    }

    func load(force: Bool = false, rediscover: Bool = true) {
        guard let discover, let standings, task == nil,
              force || (lastAttempt?.timeIntervalSinceNow ?? -.infinity) < -900 else { return }
        lastAttempt = Date()
        loading = true
        rows = nil
        error = nil
        task = Task {
            defer {
                if !Task.isCancelled { task = nil; loading = false }
            }
            do {
                if rediscover || organizations == nil {
                    let available = try await discover()
                    try Task.checkCancellation()
                    organizations = available
                    if organization == nil { selectedID = available.first?.id ?? "" }
                }
                if let organization {
                    let result = try await standings(organization)
                    try Task.checkCancellation()
                    rows = result
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct OrganizationLeaderboardCard: View {
    @ObservedObject var leaderboard: OrganizationLeaderboard
    var preview = false
    @State private var limit = 5

    var body: some View {
        Card {
            sectionHeading("ORGANIZATION LEADERBOARD")
            if preview {
                detail("Compare visible contribution activity within an organization.")
            } else {
                if let org = leaderboard.organization {
                    Text(org.login).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                if leaderboard.loading {
                    ProgressView(leaderboard.organizations == nil ? "Finding organizations…" : "Ranking visible members…")
                        .controlSize(.small).font(.system(size: 11)).padding(.vertical, 6)
                } else if let error = leaderboard.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.gold)
                    Button("Try again") { leaderboard.load(force: true) }.buttonStyle(QuietButtonStyle()).font(.system(size: 11))
                } else if let rows = leaderboard.rows {
                    if rows.isEmpty { detail("GitHub returned no visible members to rank.") }
                    else { rankings(rows) }
                } else if leaderboard.organizations?.isEmpty == true {
                    detail("No organizations are visible to this GitHub CLI session.")
                } else {
                    detail("Connect an eligible GitHub CLI session to rank organization members.")
                }
            }
        }.onChange(of: leaderboard.selectedID) { limit = 5 }
    }

    private func rankings(_ rows: [OrganizationStanding]) -> some View {
        let viewer = rows.first { isViewer($0) }
        return VStack(alignment: .leading, spacing: 8) {
            if let viewer {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        sectionHeading("YOUR PLACE")
                        Text("#\(viewer.rank.formatted()) of \(rows.count.formatted())").font(.system(size: 19, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 8)
                    Text("\(viewer.count.formatted()) contributions").font(.system(size: 11, weight: .medium)).monospacedDigit()
                }.padding(9).background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            } else {
                detail("Your account isn’t in the visible roster, so no personal rank is available.")
            }
            detail("Last 30 days · visible commits, issues, PRs and reviews. Hidden activity isn’t counted.")
            if rows.first?.count == 0 { detail("No visible activity in this period. All ranked members are tied.") }
            let shown = rows.prefix(limit)
            ForEach(shown) { row in
                HStack(spacing: 8) {
                    Text("#\(row.rank.formatted())").monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    PersonAvatar(person: row.person, size: 21)
                    Link(row.person.displayName, destination: URL(string: "https://github.com/\(row.person.login)")!)
                        .buttonStyle(QuietButtonStyle()).lineLimit(1).help("@\(row.person.login)")
                    if isViewer(row) { Text("You").foregroundStyle(Theme.accent) }
                    Spacer(minLength: 4)
                    Text(row.count.formatted()).monospacedDigit()
                }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 4)
                if row.id != shown.last?.id { Divider().opacity(0.35) }
            }
            if rows.count > limit {
                Button("Show more (\(rows.count - limit) remaining)") { limit += 10 }
                    .buttonStyle(QuietButtonStyle()).font(.system(size: 11))
            }
        }
    }

    private func isViewer(_ row: OrganizationStanding) -> Bool {
        row.person.login.caseInsensitiveCompare(leaderboard.login) == .orderedSame
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct OrganizationLeaderboardSettings: View {
    @ObservedObject var leaderboard: OrganizationLeaderboard

    var body: some View {
        if let organizations = leaderboard.organizations, !organizations.isEmpty {
            ChoiceMenu(title: "Organization", selection: Binding(get: { leaderboard.selectedID }, set: { leaderboard.select($0) }),
                       options: organizations.map { ($0.id, $0.login) })
            Text("Rank members by the activity visible to your GitHub CLI session.").foregroundStyle(.secondary)
        } else if leaderboard.loading {
            ProgressView("Finding organizations…").controlSize(.small)
        } else if let error = leaderboard.error {
            Text(error).foregroundStyle(Theme.gold)
            Button("Try again") { leaderboard.load(force: true) }.buttonStyle(QuietButtonStyle())
        } else {
            Text("No organizations are visible to this GitHub CLI session.").foregroundStyle(.secondary)
        }
    }
}
