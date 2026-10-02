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
    @Published var organizations: [TrackedOrg] = []
    @Published var workflowListMode: WorkflowListMode = .active

    // Auto-refresh
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 60
    private var lastRepoRefresh: Date = .distantPast
    private var tokens: [UUID: String] = [:]

    private let service = GitHubService()
    private let recentWorkflowLimit = 30
    /// Only poll Actions for repos pushed within this window.
    private let pollPushedWithinDays = 3
    /// Cap how many recently-pushed repos we hit each cycle.
    private let maxReposToPoll = 30
    /// Refresh repo metadata (including pushed_at) this often.
    private let repoListRefreshInterval: TimeInterval = 10 * 60

    private static let orgsDefaultsKey = "trackedOrganizations"
    private static let legacyOrgKey = "orgName"
    private static let legacyTokenKey = "githubToken"

    var refreshIntervalSeconds: Int {
        Int(refreshInterval)
    }

    var hasConfiguration: Bool {
        organizations.contains { org in
            !org.login.isEmpty && !(tokens[org.id] ?? "").isEmpty
        }
    }

    var shouldGroupReposByOrg: Bool {
        organizations.count > 1
    }

    /// Repos worth polling for Actions: recently pushed, plus anything already active / selected.
    private var reposToPoll: [GitHubRepo] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(pollPushedWithinDays) * 24 * 60 * 60)
        var selected = repos
            .filter { repo in
                guard let pushed = repo.pushedAtDate else { return false }
                return pushed >= cutoff
            }
            .sorted { ($0.pushedAtDate ?? .distantPast) > ($1.pushedAtDate ?? .distantPast) }

        if selected.count > maxReposToPoll {
            selected = Array(selected.prefix(maxReposToPoll))
        }

        var ids = Set(selected.map(\.id))

        if let selectedRepo, !ids.contains(selectedRepo.id) {
            selected.append(selectedRepo)
            ids.insert(selectedRepo.id)
        }

        for active in activeWorkflows where !ids.contains(active.repo.id) {
            selected.append(active.repo)
            ids.insert(active.repo.id)
        }

        return selected
    }

    // MARK: - Active Workflows (across all orgs and repos)

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

    var recentWorkflows: [ActiveWorkflow] {
        Array(
            allRunsByRepo.flatMap { fullName, runs in
                runs.compactMap { run in
                    repos.first(where: { $0.fullName == fullName }).map { repo in
                        ActiveWorkflow(repo: repo, run: run)
                    }
                }
            }
            .sorted { $0.run.createdAt > $1.run.createdAt }
            .prefix(recentWorkflowLimit)
        )
    }

    var displayedWorkflows: [ActiveWorkflow] {
        switch workflowListMode {
        case .active: return activeWorkflows
        case .recent: return recentWorkflows
        }
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

    func token(forOrgId id: UUID) -> String {
        tokens[id] ?? ""
    }

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: Self.orgsDefaultsKey),
           let decoded = try? JSONDecoder().decode([TrackedOrg].self, from: data),
           !decoded.isEmpty {
            organizations = decoded
            var loaded: [UUID: String] = [:]
            for org in organizations {
                loaded[org.id] = KeychainManager.read(key: Self.tokenKey(org.id)) ?? ""
            }
            tokens = loaded
            return
        }

        migrateLegacySettings()
    }

    func saveOrganizations(_ items: [(TrackedOrg, String)]) {
        let newIds = Set(items.map { $0.0.id })
        for old in organizations where !newIds.contains(old.id) {
            KeychainManager.delete(key: Self.tokenKey(old.id))
        }

        organizations = items.map(\.0)
        tokens = Dictionary(uniqueKeysWithValues: items.map { ($0.0.id, $0.1) })
        persistOrganizations()

        for (org, token) in items {
            KeychainManager.save(key: Self.tokenKey(org.id), value: token)
        }

        showSettings = false
        errorMessage = nil

        if hasConfiguration {
            Task { await loadRepos() }
        } else {
            repos = []
            workflowRuns = []
            allRunsByRepo = [:]
            selectedRepo = nil
            stopAutoRefresh()
        }
    }

    // MARK: - Data Loading

    func loadRepos() async {
        guard hasConfiguration else { return }
        isLoading = true
        errorMessage = nil

        var combined: [GitHubRepo] = []
        var errors: [String] = []

        for org in organizations where org.loadAllRepositories {
            let token = tokens[org.id] ?? ""
            guard !org.login.isEmpty, !token.isEmpty else { continue }
            do {
                let fetched = try await service.fetchRepos(owner: org.login, token: token)
                combined.append(contentsOf: fetched)
            } catch {
                errors.append("\(org.login): \(error.localizedDescription)")
            }
        }

        var seen = Set<Int>()
        repos = combined
            .sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
            .filter { seen.insert($0.id).inserted }
        lastRepoRefresh = Date()

        if selectedRepo == nil, let first = repos.first {
            selectedRepo = first
        } else if let selected = selectedRepo, !repos.contains(selected) {
            selectedRepo = repos.first
        }

        sidebarSelection = .active

        if !repos.isEmpty {
            startAutoRefresh()
            await loadAllWorkflowRuns()
        } else {
            stopAutoRefresh()
            workflowRuns = []
            allRunsByRepo = [:]
        }

        if !errors.isEmpty {
            errorMessage = errors.joined(separator: " · ")
        }

        isLoading = false
    }

    func selectSidebarItem(_ item: SidebarSelection) {
        sidebarSelection = item
        switch item {
        case .active:
            break
        case .repo(let repo):
            Task { await ensureRunsLoaded(for: repo) }
        }
    }

    func ensureRunsLoaded(for repo: GitHubRepo) async {
        selectedRepo = repo
        if let existing = allRunsByRepo[repo.fullName] {
            workflowRuns = existing
            return
        }

        let token = token(for: repo)
        guard !token.isEmpty else {
            workflowRuns = []
            return
        }

        let runs = await service.fetchAllWorkflowRuns(reposWithTokens: [(repo, token)])
        if let repoRuns = runs[repo.fullName] {
            allRunsByRepo[repo.fullName] = repoRuns
            workflowRuns = repoRuns
        } else {
            workflowRuns = []
        }
    }

    func loadAllWorkflowRuns() async {
        guard hasConfiguration else { return }

        if Date().timeIntervalSince(lastRepoRefresh) >= repoListRefreshInterval {
            await refreshRepoList()
        }

        await pollWorkflowRuns()
    }

    func refresh() async {
        await refreshRepoList()
        await pollWorkflowRuns()
    }

    /// Soft-refresh repo metadata so `pushed_at` stays current without wiping the UI.
    private func refreshRepoList() async {
        var combined: [GitHubRepo] = []
        var anySuccess = false

        for org in organizations where org.loadAllRepositories {
            let token = tokens[org.id] ?? ""
            guard !org.login.isEmpty, !token.isEmpty else { continue }
            do {
                let fetched = try await service.fetchRepos(owner: org.login, token: token)
                combined.append(contentsOf: fetched)
                anySuccess = true
            } catch {
                // Keep the existing list if an org fails mid-refresh.
            }
        }

        guard anySuccess else { return }

        var seen = Set<Int>()
        repos = combined
            .sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
            .filter { seen.insert($0.id).inserted }
        lastRepoRefresh = Date()

        if let selected = selectedRepo, !repos.contains(selected) {
            selectedRepo = repos.first
        }
    }

    private func pollWorkflowRuns() async {
        let toPoll = reposToPoll
        let jobs: [(GitHubRepo, String)] = toPoll.compactMap { repo in
            let token = token(for: repo)
            guard !token.isEmpty else { return nil }
            return (repo, token)
        }

        guard !jobs.isEmpty else {
            lastUpdated = Date()
            return
        }

        let runs = await service.fetchAllWorkflowRuns(reposWithTokens: jobs)

        var merged = allRunsByRepo
        for (fullName, repoRuns) in runs {
            merged[fullName] = repoRuns
        }
        let validNames = Set(repos.map(\.fullName))
        allRunsByRepo = merged.filter { validNames.contains($0.key) }

        if let selected = selectedRepo {
            workflowRuns = allRunsByRepo[selected.fullName] ?? []
        }

        lastUpdated = Date()

        if errorMessage?.hasPrefix("No workflow runs found") == true {
            errorMessage = nil
        }
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

    func repos(for org: TrackedOrg) -> [GitHubRepo] {
        repos.filter { $0.owner.caseInsensitiveCompare(org.login) == .orderedSame }
    }

    func runs(for repo: GitHubRepo) -> [WorkflowRun] {
        allRunsByRepo[repo.fullName] ?? []
    }

    func activeRunCount(for repo: GitHubRepo) -> Int {
        guard let runs = allRunsByRepo[repo.fullName] else { return 0 }
        return runs.filter { $0.status == "in_progress" || $0.status == "queued" }.count
    }

    func latestStatus(for repo: GitHubRepo) -> WorkflowStatus? {
        guard let runs = allRunsByRepo[repo.fullName], let latest = runs.first else { return nil }
        return latest.statusColor
    }

    // MARK: - Persistence

    private func token(for repo: GitHubRepo) -> String {
        organizations.first { $0.login.caseInsensitiveCompare(repo.owner) == .orderedSame }
            .flatMap { tokens[$0.id] } ?? ""
    }

    private func persistOrganizations() {
        if let data = try? JSONEncoder().encode(organizations) {
            UserDefaults.standard.set(data, forKey: Self.orgsDefaultsKey)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyOrgKey)
        KeychainManager.delete(key: Self.legacyTokenKey)
    }

    private func migrateLegacySettings() {
        let legacyOrg = UserDefaults.standard.string(forKey: Self.legacyOrgKey) ?? ""
        let legacyToken = KeychainManager.read(key: Self.legacyTokenKey) ?? ""
        guard !legacyOrg.isEmpty else { return }

        let org = TrackedOrg(id: UUID(), login: legacyOrg, loadAllRepositories: true)
        organizations = [org]
        tokens = [org.id: legacyToken]
        persistOrganizations()
        if !legacyToken.isEmpty {
            KeychainManager.save(key: Self.tokenKey(org.id), value: legacyToken)
            KeychainManager.delete(key: Self.legacyTokenKey)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyOrgKey)
    }

    private static func tokenKey(_ id: UUID) -> String {
        "githubToken.\(id.uuidString)"
    }
}
