import Foundation
import Combine

@MainActor
class WorkflowViewModel: ObservableObject {
    @Published var repos: [GitHubRepo] = []
    @Published var selectedRepo: GitHubRepo?
    @Published var workflowRuns: [WorkflowRun] = []
    @Published var allRunsByRepo: [String: [WorkflowRun]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var lastUpdated: Date?
    @Published var sidebarSelection: SidebarSelection = .active

    // Settings
    @Published var orgName: String = ""
    @Published var gitHubToken: String = ""

    // Auto-refresh
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 15
    private var lastRepoRefresh: Date = .distantPast

    private let service = GitHubService()

    var hasConfiguration: Bool {
        !orgName.isEmpty && !gitHubToken.isEmpty
    }

    // MARK: - Active Workflows (across all repos)

    var activeWorkflows: [ActiveWorkflow] {
        allRunsByRepo.flatMap { fullName, runs in
            runs.filter { $0.status == "in_progress" || $0.status == "queued" }
                .compactMap { run in
                    repos.first(where: { $0.fullName == fullName }).map { repo in
                        ActiveWorkflow(repo: repo, run: run)
                    }
                }
        }
        .sorted { $0.run.createdAt > $1.run.createdAt }
    }

    var activeWorkflowCount: Int {
        activeWorkflows.count
    }

    init() {
        loadSettings()
        if hasConfiguration {
            Task { await loadRepos() }
        } else {
            showSettings = true
        }
    }

    // MARK: - Settings

    func loadSettings() {
        orgName = UserDefaults.standard.string(forKey: "orgName") ?? ""
        gitHubToken = KeychainManager.read(key: "githubToken") ?? ""
    }

    func saveSettings(org: String, token: String) {
        orgName = org
        gitHubToken = token
        UserDefaults.standard.set(org, forKey: "orgName")
        KeychainManager.save(key: "githubToken", value: token)
        showSettings = false
        errorMessage = nil

        Task { await loadRepos() }
    }

    func clearSettings() {
        orgName = ""
        gitHubToken = ""
        UserDefaults.standard.removeObject(forKey: "orgName")
        KeychainManager.delete(key: "githubToken")
        repos = []
        workflowRuns = []
        allRunsByRepo = [:]
        selectedRepo = nil
        stopAutoRefresh()
    }

    // MARK: - Data Loading

    func loadRepos() async {
        guard hasConfiguration else { return }
        isLoading = true
        errorMessage = nil

        do {
            repos = try await service.fetchRepos(org: orgName, token: gitHubToken)
            lastRepoRefresh = Date()

            if selectedRepo == nil, let first = repos.first {
                selectedRepo = first
            }

            sidebarSelection = .active
            startAutoRefresh()
            await loadAllWorkflowRuns()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func selectSidebarItem(_ item: SidebarSelection) {
        sidebarSelection = item
        switch item {
        case .active:
            break // activeWorkflows is computed from allRunsByRepo
        case .repo(let repo):
            selectedRepo = repo
            workflowRuns = allRunsByRepo[repo.fullName] ?? []
        }
    }

    func loadAllWorkflowRuns() async {
        guard hasConfiguration else { return }
        errorMessage = nil

        let runs = await service.fetchAllWorkflowRuns(repos: repos, token: gitHubToken)
        allRunsByRepo = runs

        if let selected = selectedRepo {
            workflowRuns = runs[selected.fullName] ?? []
        }

        lastUpdated = Date()

        let populated = runs.values.filter { !$0.isEmpty }.count
        if populated == 0 && !repos.isEmpty {
            errorMessage = "No workflow runs found across \(repos.count) repos. Check token scopes."
        }
    }

    func refresh() async {
        await loadAllWorkflowRuns()
    }

    // MARK: - Auto-refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.loadAllWorkflowRuns()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Computed

    func activeRunCount(for repo: GitHubRepo) -> Int {
        guard let runs = allRunsByRepo[repo.fullName] else { return 0 }
        return runs.filter { $0.status == "in_progress" || $0.status == "queued" }.count
    }

    func latestStatus(for repo: GitHubRepo) -> WorkflowStatus? {
        guard let runs = allRunsByRepo[repo.fullName], let latest = runs.first else { return nil }
        return latest.statusColor
    }
}
