import Foundation

enum GitHubError: LocalizedError {
    case invalidURL
    case noData
    case rateLimited
    case unauthorized
    case notFound
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .rateLimited: return "API rate limit exceeded. Please wait."
        case .unauthorized: return "Invalid or missing GitHub token. Check settings."
        case .notFound: return "Organization or repository not found"
        case .networkError(let msg): return "Network error: \(msg)"
        case .decodingError(let msg): return "Data error: \(msg)"
        }
    }
}

class GitHubService {
    private let session: URLSession
    private let baseURL = "https://api.github.com"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Repos

    func fetchRepos(owner: String, token: String) async throws -> [GitHubRepo] {
        let encoded = Self.pathEscape(owner)
        do {
            return try await fetchPagedRepos(path: "/orgs/\(encoded)/repos", token: token)
        } catch {
            guard case GitHubError.notFound = error else { throw error }
            return try await fetchUserRepos(owner: owner, encodedOwner: encoded, token: token)
        }
    }

    /// `/users/{user}/repos` only returns public repos, even with a PAT.
    /// When the token belongs to this user, `/user/repos` includes private ones.
    private func fetchUserRepos(owner: String, encodedOwner: String, token: String) async throws -> [GitHubRepo] {
        if let me = try? await fetchAuthenticatedUser(token: token),
           me.login.caseInsensitiveCompare(owner) == .orderedSame {
            return try await fetchPagedRepos(
                path: "/user/repos",
                token: token,
                query: "affiliation=owner&sort=pushed"
            )
        }
        return try await fetchPagedRepos(
            path: "/users/\(encodedOwner)/repos",
            token: token,
            query: "type=all&sort=pushed"
        )
    }

    private func fetchAuthenticatedUser(token: String) async throws -> GitHubUser {
        let data = try await performRequest(urlString: "\(baseURL)/user", token: token)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    private func fetchPagedRepos(
        path: String,
        token: String,
        query: String = "type=all&sort=pushed"
    ) async throws -> [GitHubRepo] {
        var allRepos: [GitHubRepo] = []
        var page = 1

        while true {
            let url = "\(baseURL)\(path)?per_page=100&page=\(page)&\(query)"
            let data = try await performRequest(urlString: url, token: token)
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            allRepos.append(contentsOf: repos)
            if repos.count < 100 { break }
            page += 1
        }

        return allRepos
    }

    private struct GitHubUser: Codable {
        let login: String
    }

    // MARK: - Workflow Runs

    func fetchWorkflowRuns(owner: String, repo: String, token: String) async throws -> [WorkflowRun] {
        let url = "\(baseURL)/repos/\(Self.pathEscape(owner))/\(Self.pathEscape(repo))/actions/runs?per_page=20"
        let data = try await performRequest(urlString: url, token: token)
        let response = try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
        return response.workflowRuns
    }

    // MARK: - All Runs Across Repos

    func fetchAllWorkflowRuns(reposWithTokens: [(GitHubRepo, String)]) async -> [String: [WorkflowRun]] {
        var result: [String: [WorkflowRun]] = [:]

        await withTaskGroup(of: (String, [WorkflowRun]).self) { group in
            for (repo, token) in reposWithTokens {
                group.addTask {
                    do {
                        let runs = try await self.fetchWorkflowRuns(
                            owner: repo.owner,
                            repo: repo.name,
                            token: token
                        )
                        return (repo.fullName, runs)
                    } catch {
                        return (repo.fullName, [])
                    }
                }
            }

            for await (fullName, runs) in group {
                result[fullName] = runs
            }
        }

        return result
    }

    private static func pathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    // MARK: - Request

    private func performRequest(urlString: String, token: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            if httpResponse.allHeaderFields["X-RateLimit-Remaining"] as? String == "0" {
                throw GitHubError.rateLimited
            }
            throw GitHubError.unauthorized
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}
