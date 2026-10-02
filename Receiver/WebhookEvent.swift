import Foundation

struct WebhookEnvelope: Decodable {
    let action: String?
    let repository: Repository?
    let sender: Sender?
    let workflowRun: WorkflowRunPayload?

    enum CodingKeys: String, CodingKey {
        case action, repository, sender
        case workflowRun = "workflow_run"
    }

    struct Repository: Decodable {
        let fullName: String?
        let name: String?
        let owner: Owner?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name, owner
        }

        struct Owner: Decodable {
            let login: String?
        }

        var resolvedFullName: String {
            if let fullName, !fullName.isEmpty { return fullName }
            guard let owner = owner?.login, let name else { return "" }
            return "\(owner)/\(name)"
        }
    }

    struct Sender: Decodable {
        let login: String?
    }

    struct WorkflowRunPayload: Decodable {
        let id: Int64
        let name: String?
        let headBranch: String?
        let headSha: String?
        let status: String?
        let conclusion: String?
        let workflowId: Int64?
        let runNumber: Int?
        let event: String?
        let htmlUrl: String?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name, status, conclusion, event
            case headBranch = "head_branch"
            case headSha = "head_sha"
            case workflowId = "workflow_id"
            case runNumber = "run_number"
            case htmlUrl = "html_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    var eventName: String { "workflow_run" }

    var repoFullName: String { repository?.resolvedFullName ?? "" }
}
