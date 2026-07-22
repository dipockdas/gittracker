import Foundation

// MARK: - GitHub API Models

struct GitHubRepo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let `private`: Bool
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case `private`
        case description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GitHubRepo, rhs: GitHubRepo) -> Bool {
        lhs.id == rhs.id
    }
}

struct RepoListResponse: Codable {
    let repos: [GitHubRepo]

    init(from decoder: Decoder) throws {
        // The response is a plain JSON array of repos
        let container = try decoder.singleValueContainer()
        repos = try container.decode([GitHubRepo].self)
    }
}

struct WorkflowRun: Codable, Identifiable {
    let id: Int
    let name: String?
    let headBranch: String
    let headSha: String
    let status: String
    let conclusion: String?
    let workflowId: Int?
    let createdAt: String
    let updatedAt: String
    let htmlUrl: String?
    let event: String?
    let runNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, event
        case headBranch = "head_branch"
        case headSha = "head_sha"
        case workflowId = "workflow_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case runNumber = "run_number"
    }

    var statusColor: WorkflowStatus {
        switch status {
        case "queued":
            return .queued
        case "in_progress", "waiting":
            return .inProgress
        case "completed":
            switch conclusion {
            case "success": return .success
            case "failure": return .failure
            case "cancelled": return .cancelled
            case "skipped", "neutral": return .skipped
            case "timed_out": return .timedOut
            default: return .unknown
            }
        default:
            return .unknown
        }
    }

    var createdAtDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var relativeTime: String {
        guard let date = createdAtDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct WorkflowRunsResponse: Codable {
    let totalCount: Int
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}

// MARK: - Active Workflow (run + repo combined)

struct ActiveWorkflow: Identifiable {
    let repo: GitHubRepo
    let run: WorkflowRun
    var id: Int { run.id }
}

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case active
    case repo(GitHubRepo)
}

enum WorkflowStatus {
    case queued
    case inProgress
    case success
    case failure
    case cancelled
    case skipped
    case timedOut
    case unknown

    var color: String {
        switch self {
        case .queued: return "yellow"
        case .inProgress: return "blue"
        case .success: return "green"
        case .failure: return "red"
        case .cancelled, .skipped: return "gray"
        case .timedOut: return "orange"
        case .unknown: return "gray"
        }
    }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .inProgress: return "Running"
        case .success: return "Success"
        case .failure: return "Failed"
        case .cancelled: return "Cancelled"
        case .skipped: return "Skipped"
        case .timedOut: return "Timed Out"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        case .skipped: return "forward.fill"
        case .timedOut: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
