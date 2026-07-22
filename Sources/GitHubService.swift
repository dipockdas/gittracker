import Foundation

enum GitHubError: LocalizedError {
    case invalidURL
    case noData
    case rateLimited
    case unauthorized
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .rateLimited: return "API rate limit exceeded. Please wait."
        case .unauthorized: return "Invalid or missing GitHub token. Check settings."
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

    func fetchRepos(org: String, token: String) async throws -> [GitHubRepo] {
        var allRepos: [GitHubRepo] = []
        var page = 1

        while true {
            let url = "\(baseURL)/orgs/\(org)/repos?per_page=100&page=\(page)&type=all&sort=full_name"
            let data = try await performRequest(urlString: url, token: token)
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            allRepos.append(contentsOf: repos)
            if repos.count < 100 { break }
            page += 1
        }

        return allRepos.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Workflow Runs

    func fetchWorkflowRuns(owner: String, repo: String, token: String) async throws -> [WorkflowRun] {
        let url = "\(baseURL)/repos/\(owner)/\(repo)/actions/runs?per_page=20"
        let data = try await performRequest(urlString: url, token: token)
        let response = try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
        return response.workflowRuns
    }

    // MARK: - All Runs Across Repos

    func fetchAllWorkflowRuns(repos: [GitHubRepo], token: String) async -> [String: [WorkflowRun]] {
        var result: [String: [WorkflowRun]] = [:]

        await withTaskGroup(of: (String, [WorkflowRun]).self) { group in
            for repo in repos {
                group.addTask {
                    do {
                        let runs = try await self.fetchWorkflowRuns(
                            owner: repo.fullName.split(separator: "/").first.map(String.init) ?? "",
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
            throw GitHubError.networkError("Organization or repository not found")
        default:
            throw GitHubError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}
