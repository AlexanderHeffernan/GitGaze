import Foundation

public struct GitHubOrganization: Decodable, Identifiable, Sendable {
    public let id: String
    public let login: String
}

public struct OrganizationStanding: Identifiable, Sendable {
    public let person: Person
    public let count: Int
    public let rank: Int
    public var id: String { person.login }

    public init(person: Person, count: Int, rank: Int) {
        self.person = person
        self.count = count
        self.rank = rank
    }
}

public extension GitHubClient {
    func organizations() async throws -> [GitHubOrganization] {
        try await OrganizationQueries.organizations(query: query)
    }

    func organizationStandings(for organization: GitHubOrganization) async throws -> [OrganizationStanding] {
        try await OrganizationQueries.standings(for: organization, query: query)
    }
}

enum OrganizationQueries {
    typealias Query = @Sendable (String, [String: String]) async throws -> Data
    static let memberLimit = 500
    private static let pageSize = 25

    static func organizations(query: Query) async throws -> [GitHubOrganization] {
        let pages: [OrganizationNode] = try await collect { after in
            let data = try await query("""
                query($after:String) { viewer { organizations(first:100,after:$after) {
                  nodes { id login viewerIsAMember } pageInfo { hasNextPage endCursor }
                } } }
                """, after.map { ["after": $0] } ?? [:])
            return try JSONDecoder().decode(OrganizationsEnvelope.self, from: data).data.viewer.organizations
        }
        var seen = Set<String>()
        return pages.filter { $0.viewerIsAMember && seen.insert($0.id).inserted }.map {
            GitHubOrganization(id: $0.id, login: $0.login)
        }.sorted { $0.login.lowercased() < $1.login.lowercased() }
    }

    static func standings(for org: GitHubOrganization, now: Date = Date(), query: Query) async throws -> [OrganizationStanding] {
        let format = ISO8601DateFormatter()
        let from = format.string(from: now.addingTimeInterval(-30 * 86_400))
        let to = format.string(from: now)
        let members: [Member] = try await collect { after in
            var variables = ["login": org.login, "org": org.id, "from": from, "to": to]
            variables["after"] = after
            let data = try await query("""
                query($login:String!, $org:ID!, $from:DateTime!, $to:DateTime!, $after:String) {
                  organization(login:$login) {
                    id viewerIsAMember
                    membersWithRole(first:\(pageSize),after:$after) {
                      totalCount pageInfo { hasNextPage endCursor }
                      nodes { login name avatarUrl
                        contributionsCollection(organizationID:$org,from:$from,to:$to) {
                          totalCommitContributions totalIssueContributions
                          totalPullRequestContributions totalPullRequestReviewContributions
                        }
                      }
                    }
                  }
                }
                """, variables)
            guard let orgData = try JSONDecoder().decode(MembersEnvelope.self, from: data).data.organization,
                  orgData.id == org.id, orgData.viewerIsAMember else {
                throw GitHubError.message("This organization is no longer available to your GitHub CLI session.")
            }
            let page = orgData.membersWithRole
            guard let total = page.totalCount else { throw incompleteRoster }
            guard total <= memberLimit else {
                throw GitHubError.message("GitGaze can rank up to \(memberLimit) visible members. This organization is larger.")
            }
            return page
        }
        guard Set(members.map { $0.person.login.lowercased() }).count == members.count else { throw incompleteRoster }
        let sorted = members.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.person.login.lowercased() < $1.person.login.lowercased()
        }
        var rank = 0
        return sorted.enumerated().map { index, member in
            if index == 0 || sorted[index - 1].count != member.count { rank = index + 1 }
            return OrganizationStanding(person: member.person, count: member.count, rank: rank)
        }
    }

    private static let incompleteRoster = GitHubError.message("GitHub's visible member list changed or was incomplete. Try again.")

    private static func collect<Node>(_ fetch: (String?) async throws -> Page<Node>) async throws -> [Node] {
        var nodes: [Node] = []
        var cursor: String?
        var seenCursors = Set<String>()
        var total: Int?
        repeat {
            try Task.checkCancellation()
            let page = try await fetch(cursor)
            if let total, page.totalCount != total { throw incompleteRoster }
            total = page.totalCount
            nodes += page.nodes.compactMap { $0 }
            guard !page.pageInfo.hasNextPage else {
                if let next = page.pageInfo.endCursor, seenCursors.insert(next).inserted,
                   total == nil || seenCursors.count < memberLimit / pageSize {
                    cursor = next
                    continue
                }
                throw GitHubError.message("GitHub didn't return the full visible organization list. Try again.")
            }
            if let total, nodes.count != total { throw incompleteRoster }
            return nodes
        } while true
    }

    private struct Page<Node: Decodable>: Decodable {
        let nodes: [Node?]
        let pageInfo: PageInfo
        let totalCount: Int?
        struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
    }

    private struct OrganizationNode: Decodable { let id: String; let login: String; let viewerIsAMember: Bool }
    private struct OrganizationsEnvelope: Decodable {
        let data: Payload
        struct Payload: Decodable {
            let viewer: Viewer
            struct Viewer: Decodable { let organizations: Page<OrganizationNode> }
        }
    }

    private struct MembersEnvelope: Decodable {
        let data: Payload
        struct Payload: Decodable {
            let organization: Organization?
            struct Organization: Decodable {
                let id: String
                let viewerIsAMember: Bool
                let membersWithRole: Page<Member>
            }
        }
    }

    private struct Member: Decodable {
        let person: Person
        let count: Int

        init(from decoder: Decoder) throws {
            person = try Person(from: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
                .decode(Counts.self, forKey: .contributionsCollection)
            count = values.totalCommitContributions + values.totalIssueContributions
                + values.totalPullRequestContributions + values.totalPullRequestReviewContributions
        }

        private enum CodingKeys: CodingKey { case contributionsCollection }
        private struct Counts: Decodable {
            let totalCommitContributions: Int
            let totalIssueContributions: Int
            let totalPullRequestContributions: Int
            let totalPullRequestReviewContributions: Int
        }
    }
}
