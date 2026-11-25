import Foundation

public enum GitHubError: LocalizedError {
    case message(String)
    case classified(String, code: String)
    public var code: String {
        if case .classified(_, let code) = self { return code }
        return "unknown"
    }
    public var errorDescription: String? {
        switch self { case .message(let message), .classified(let message, _): return message }
    }
}

public struct GitHubClient: Sendable {
    public let token: String
    public init(token: String) { self.token = token }

    public func query(_ query: String, variables: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GitGaze/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed].contains(error.code) {
            throw GitHubError.classified(error.localizedDescription, code: "network")
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.message("GitHub did not respond.") }
        if http.statusCode == 401 { throw GitHubError.classified("Your GitHub CLI session expired. Run gh auth login, then relaunch GitGaze.", code: "access") }
        if http.statusCode == 403 || http.statusCode == 429 {
            if http.value(forHTTPHeaderField: "x-github-sso")?.lowercased().hasPrefix("required") == true {
                throw GitHubError.classified("GitHub requires organization SSO authorization.", code: "access")
            }
            let limited = http.statusCode == 429 || http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http.value(forHTTPHeaderField: "retry-after") != nil
            throw GitHubError.classified(limited ? "GitHub is limiting requests. Try again later." : "GitHub denied access. Check your GitHub CLI authorization.", code: limited ? "rate_limit" : "access")
        }
        guard http.statusCode == 200 else { throw GitHubError.classified("GitHub returned HTTP \(http.statusCode). Try again shortly.", code: http.statusCode >= 500 ? "server" : "unknown") }
        let envelope = try JSONDecoder().decode(ErrorEnvelope.self, from: data)
        if let errors = envelope.errors, let error = errors.first {
            let types = Set(errors.compactMap(\.type))
            let code = !types.isDisjoint(with: ["FORBIDDEN", "UNAUTHORIZED", "NOT_FOUND", "SAML_ENFORCEMENT", "INSUFFICIENT_SCOPES"]) ? "access" :
                errors.allSatisfy { $0.type == "RATE_LIMITED" } ? "rate_limit" : "unknown"
            throw GitHubError.classified(error.message, code: code)
        }
        return data
    }

    private static let collection = """
        contributionYears restrictedContributionsCount
        contributionCalendar { totalContributions weeks { contributionDays { date contributionCount color } } }
        """

    public func viewer() async throws -> Profile {
        let data = try await query("query { viewer { login name avatarUrl contributionsCollection { \(Self.collection) } } }")
        return try JSONDecoder().decode(ViewerEnvelope.self, from: data).data.viewer.profile
    }

    public func profile(login: String) async throws -> Profile {
        let data = try await query("query($login:String!) { user(login:$login) { login name avatarUrl contributionsCollection { \(Self.collection) } } }", variables: ["login": login])
        guard let user = try JSONDecoder().decode(UserEnvelope.self, from: data).data.user else {
            throw GitHubError.message("This GitHub profile is no longer available.")
        }
        return user.profile
    }

    public func history(login: String, year: Int) async throws -> [ContributionDay] {
        let data = try await query("""
            query($login:String!, $from:DateTime!, $to:DateTime!) {
              user(login:$login) { login name avatarUrl contributionsCollection(from:$from,to:$to) { \(Self.collection) } }
            }
            """, variables: ["login": login, "from": "\(year)-01-01T00:00:00Z", "to": "\(year)-12-31T23:59:59Z"])
        guard let user = try JSONDecoder().decode(UserEnvelope.self, from: data).data.user else {
            throw GitHubError.message("This GitHub profile is no longer available.")
        }
        return user.profile.days
    }

    public func following() async throws -> [Person] {
        var people: [Person] = []
        var cursor: String?
        repeat {
            let after = cursor.map { ", after: \"\($0)\"" } ?? ""
            let data = try await query("query { viewer { following(first:100\(after)) { nodes { login name avatarUrl } pageInfo { hasNextPage endCursor } } } }")
            let page = try JSONDecoder().decode(FollowingEnvelope.self, from: data).data.viewer.following
            people += page.nodes
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil
        return people
    }
}

private struct ErrorEnvelope: Decodable { var errors: [APIError]? }
private struct APIError: Decodable { var message: String; var type: String? }
private struct ViewerEnvelope: Decodable { var data: ViewerData }
private struct ViewerData: Decodable { var viewer: APIUser }
private struct UserEnvelope: Decodable { var data: UserData }
private struct UserData: Decodable { var user: APIUser? }
private struct APIUser: Decodable {
    var login: String
    var name: String?
    var avatarUrl: String
    var contributionsCollection: Collection
    var profile: Profile {
        Profile(person: Person(login: login, name: name, avatarUrl: avatarUrl),
                days: contributionsCollection.contributionCalendar.weeks.flatMap(\.contributionDays),
                years: contributionsCollection.contributionYears,
                totalContributions: contributionsCollection.contributionCalendar.totalContributions,
                restrictedCount: contributionsCollection.restrictedContributionsCount)
    }
}
private struct Collection: Decodable {
    var contributionYears: [Int]
    var restrictedContributionsCount: Int
    var contributionCalendar: ContributionCalendar
}
private struct ContributionCalendar: Decodable {
    var totalContributions: Int
    var weeks: [Week]
    struct Week: Decodable { var contributionDays: [ContributionDay] }
}
private struct FollowingEnvelope: Decodable {
    var data: DataValue
    struct DataValue: Decodable {
        var viewer: Viewer
        struct Viewer: Decodable { var following: Connection }
    }
    struct Connection: Decodable { var nodes: [Person]; var pageInfo: PageInfo }
    struct PageInfo: Decodable { var hasNextPage: Bool; var endCursor: String? }
}
