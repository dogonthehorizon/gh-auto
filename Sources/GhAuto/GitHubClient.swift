import Foundation

struct PullRequest: Decodable, Sendable, Equatable {
    struct Repository: Decodable, Sendable, Equatable {
        let nameWithOwner: String
    }

    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let repository: Repository
}

enum GitHubError: LocalizedError {
    case ghNotFound
    case ghAuthFailed(String)
    case http(Int)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .ghNotFound: "gh CLI not found. Install it with `brew install gh`."
        case .ghAuthFailed(let message): "gh auth token failed: \(message)"
        case .http(let status): "GitHub returned HTTP \(status)"
        case .graphQL(let message): "GitHub GraphQL error: \(message)"
        }
    }
}

/// Fetches the viewer's open pull requests with a single GraphQL search call.
/// The token comes from the gh CLI so there's nothing to store or rotate here.
actor GitHubClient {
    static let searchQuery = "is:pr is:open author:@me archived:false sort:updated-desc"

    private static let graphQLQuery = """
        query($q: String!) {
          search(query: $q, type: ISSUE, first: 50) {
            nodes {
              ... on PullRequest {
                number title url isDraft
                repository { nameWithOwner }
              }
            }
          }
        }
        """

    // GUI apps launch with a minimal PATH, so look in the usual install locations.
    private static let ghCandidates = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    private let session = URLSession(configuration: .ephemeral)
    private var token: String?

    func fetchOpenPullRequests() async throws -> [PullRequest] {
        do {
            return try await search(token: currentToken())
        } catch GitHubError.http(401) {
            // Token was rotated by `gh auth refresh`/`login`; reread it once.
            token = nil
            return try await search(token: currentToken())
        }
    }

    private func currentToken() throws -> String {
        if let token { return token }
        let fresh = try Self.readGhToken()
        token = fresh
        return fresh
    }

    private func search(token: String) async throws -> [PullRequest] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("gh-auto", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(query: Self.graphQLQuery, variables: ["q": Self.searchQuery])
        )

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GitHubError.http(status) }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        if let message = decoded.errors?.first?.message { throw GitHubError.graphQL(message) }
        // Non-PR search hits decode as empty objects; drop them.
        return decoded.data?.search.nodes.compactMap(\.pullRequest) ?? []
    }

    private static func readGhToken() throws -> String {
        guard let gh = ghCandidates.first(where: FileManager.default.isExecutableFile) else {
            throw GitHubError.ghNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token", "--hostname", "github.com"]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !out.isEmpty else {
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw GitHubError.ghAuthFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct SearchResponse: Decodable {
    struct Payload: Decodable {
        struct Search: Decodable { let nodes: [Node] }
        let search: Search
    }

    struct Node: Decodable {
        let pullRequest: PullRequest?
        init(from decoder: Decoder) throws {
            pullRequest = try? PullRequest(from: decoder)
        }
    }

    struct Message: Decodable { let message: String }

    let data: Payload?
    let errors: [Message]?
}
