import Foundation

let secret = ReceiverConfig.secret
let store: RunStore

do {
    store = try RunStore(path: ReceiverConfig.databasePath)
} catch {
    ReceiverConfig.log("fatal: cannot open database at \(ReceiverConfig.databasePath): \(error)")
    exit(1)
}

if secret == nil {
    ReceiverConfig.log("WARNING: no webhook secret configured. Set \(ReceiverConfig.secretFilePath) or GITTRACKER_WEBHOOK_SECRET.")
    ReceiverConfig.log("WARNING: all deliveries will be rejected until a secret exists.")
}

func handle(_ request: HTTPRequest) -> HTTPResponse {
    let event = request.headers["x-github-event"] ?? ""
    let deliveryID = request.headers["x-github-delivery"] ?? ""

    if request.method == "GET" {
        if request.path == "/health" {
            return .json([
                "status": "ok",
                "repos": store.activeRepoCount(),
                "runs": store.runCount(),
                "secretConfigured": secret != nil,
            ])
        }
        return .notFound
    }

    guard request.method == "POST" else { return .notFound }

    if event == "ping" {
        ReceiverConfig.log("ping from GitHub (delivery \(deliveryID)) — webhook is live")
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: nil, repo: nil,
            runID: nil, outcome: "ping", detail: nil
        )
        return .json(["status": "pong"])
    }

    guard event == "workflow_run" else {
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: nil, repo: nil,
            runID: nil, outcome: "ignored_event", detail: nil
        )
        return .json(["status": "ignored", "event": event])
    }

    switch WebhookVerifier.verify(body: request.body, headers: request.headers, secret: secret) {
    case .notConfigured:
        return .json(
            ["error": "receiver has no webhook secret configured"], status: 503, reason: "Service Unavailable"
        )
    case .missing:
        ReceiverConfig.log("rejected delivery \(deliveryID): no X-Hub-Signature-256 header")
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: nil, repo: nil,
            runID: nil, outcome: "rejected_missing_signature", detail: nil
        )
        return .json(["error": "missing signature"], status: 401, reason: "Unauthorized")
    case .invalid:
        let repo = (try? JSONDecoder().decode(WebhookEnvelope.self, from: request.body))?.repoFullName ?? ""
        ReceiverConfig.log("rejected delivery \(deliveryID): bad signature for \(repo)")
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: nil, repo: repo.isEmpty ? nil : repo,
            runID: nil, outcome: "rejected_bad_signature", detail: nil
        )
        return .json(["error": "invalid signature"], status: 401, reason: "Unauthorized")
    case .valid:
        break
    }

    let envelope: WebhookEnvelope
    do {
        envelope = try JSONDecoder().decode(WebhookEnvelope.self, from: request.body)
    } catch {
        ReceiverConfig.log("rejected delivery \(deliveryID): undecodable payload \(error)")
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: nil,
            repo: nil, runID: nil, outcome: "rejected_bad_payload", detail: "\(error)"
        )
        return .json(["error": "undecodable payload"], status: 400, reason: "Bad Request")
    }

    guard let run = envelope.workflowRun else {
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: envelope.action, repo: envelope.repoFullName,
            runID: nil, outcome: "no_workflow_run", detail: nil
        )
        return .json(["status": "accepted", "stored": false])
    }

    let repo = envelope.repoFullName
    guard !repo.isEmpty else {
        store.recordDelivery(
            deliveryID: deliveryID, event: event, action: envelope.action, repo: nil,
            runID: run.id, outcome: "rejected_no_repo", detail: nil
        )
        return .json(["error": "missing repository"], status: 400, reason: "Bad Request")
    }

    store.upsertRun(repo: repo, run: run, action: envelope.action)
    store.recordDelivery(
        deliveryID: deliveryID, event: event, action: envelope.action, repo: repo,
        runID: run.id, outcome: "stored", detail: nil
    )
    ReceiverConfig.log("\(repo) run #\(run.runNumber.map(String.init) ?? "?") \(run.name ?? "") [\(envelope.action ?? "?")] → \(run.status ?? "?")/\(run.conclusion ?? "-")")

    return .json(["status": "accepted"])
}

let server = HTTPServer(port: ReceiverConfig.port, handler: handle)

do {
    try server.start()
    ReceiverConfig.log("gittracker-receiver listening on http://127.0.0.1:\(ReceiverConfig.port)")
    ReceiverConfig.log("database: \(ReceiverConfig.databasePath)")
} catch {
    ReceiverConfig.log("fatal: cannot listen on port \(ReceiverConfig.port): \(error)")
    exit(1)
}

dispatchMain()
