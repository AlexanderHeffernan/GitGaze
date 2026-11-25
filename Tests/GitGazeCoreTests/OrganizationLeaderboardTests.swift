import Foundation
import Testing
@testable import GitGazeCore

struct OrganizationLeaderboardTests {
    @Test func listsOnlyActiveMembershipsAcrossPages() async throws {
        let organizations = try await OrganizationQueries.organizations { _, variables in
            if variables["after"] == nil {
                return Data(#"{"data":{"viewer":{"organizations":{"nodes":[{"id":"3","login":"Zeta","viewerIsAMember":true},{"id":"2","login":"pending","viewerIsAMember":false}],"pageInfo":{"hasNextPage":true,"endCursor":"opaque"}}}}}"#.utf8)
            }
            #expect(variables["after"] == "opaque")
            return Data(#"{"data":{"viewer":{"organizations":{"nodes":[{"id":"1","login":"alpha","viewerIsAMember":true}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#.utf8)
        }
        #expect(organizations.map(\.login) == ["alpha", "Zeta"])
    }

    @Test func ranksAllVisiblePagesByScopedCountsWithCompetitionTies() async throws {
        let org = GitHubOrganization(id: "org-id", login: "org-login")
        let end = try #require(ISO8601DateFormatter().date(from: "2025-03-03T07:40:00Z"))
        let rows = try await OrganizationQueries.standings(for: org, now: end) { query, variables in
            #expect(query.contains("contributionsCollection(organizationID:$org,from:$from,to:$to)"))
            #expect(!query.contains("contributionCalendar") && !query.contains("restrictedContributionsCount"))
            #expect(variables["org"] == "org-id" && variables["login"] == "org-login")
            #expect(variables["from"] == "2025-02-01T07:40:00Z" && variables["to"] == "2025-03-03T07:40:00Z")
            if variables["after"] == nil {
                return roster([member("Zeke", 6), member("quiet", 0)], total: 4, next: "p2")
            }
            #expect(variables["after"] == "p2")
            return roster([member("alice", 0, 2, 3, 1), member("viewer", 1, 2, 3, 4)], total: 4)
        }
        #expect(rows.map(\.person.login) == ["viewer", "alice", "Zeke", "quiet"])
        #expect(rows.map(\.count) == [10, 6, 6, 0])
        #expect(rows.map(\.rank) == [1, 2, 2, 4])
    }

    @Test func withholdsRankForIncompleteOrOversizedRosters() async throws {
        let org = GitHubOrganization(id: "org-id", login: "org-login")
        for result in [roster([member("one", 3)], total: 2),
                       roster([member("one", 3), member("One", 3)], total: 2),
                       roster([], total: 501, next: "no-followup"),
                       roster([member("one", 3)], total: 1, active: false)] {
            await #expect(throws: GitHubError.self) {
                try await OrganizationQueries.standings(for: org) { _, variables in
                    #expect(variables["after"] == nil)
                    return result
                }
            }
        }
    }

    private func roster(_ members: [String], total: Int, next: String? = nil, active: Bool = true) -> Data {
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return Data("""
            {"data":{"organization":{"id":"org-id","viewerIsAMember":\(active),"membersWithRole":{
            "nodes":[\(members.joined(separator: ","))],"totalCount":\(total),
            "pageInfo":{"hasNextPage":\(next != nil),"endCursor":\(cursor)}}}}}
            """.utf8)
    }

    private func member(_ login: String, _ commits: Int, _ issues: Int = 0, _ prs: Int = 0, _ reviews: Int = 0) -> String {
        """
        {"login":"\(login)","avatarUrl":"","contributionsCollection":{"totalCommitContributions":\(commits),
        "totalIssueContributions":\(issues),"totalPullRequestContributions":\(prs),
        "totalPullRequestReviewContributions":\(reviews),"restrictedContributionsCount":200}}
        """
    }
}
