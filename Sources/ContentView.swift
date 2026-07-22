import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: WorkflowViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
        .task {
            if viewModel.hasConfiguration {
                await viewModel.loadRepos()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.blue)
                Text("GitTracker")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Org name
            if !viewModel.orgName.isEmpty {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundStyle(.secondary)
                    Text(viewModel.orgName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            // Refresh status
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                Text(viewModel.isLoading ? "Loading..." : "Auto-refresh 15s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = viewModel.lastUpdated {
                    Text(last, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Error message
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor).opacity(0.5))
            }

            // Sidebar list
            List(selection: $viewModel.sidebarSelection) {
                // Active Workflows — always first
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                            .font(.body)
                        Text("Active Workflows")
                            .font(.body)
                        Spacer()
                        let count = viewModel.activeWorkflowCount
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue))
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(SidebarSelection.active)
                }

                // Repositories
                Section("Repositories") {
                    if viewModel.repos.isEmpty && !viewModel.isLoading {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "tray")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                                Text("No repositories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.repos, id: \.self) { repo in
                            RepoRow(repo: repo)
                                .tag(SidebarSelection.repo(repo))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 240)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.sidebarSelection {
        case .active:
            activeWorkflowsView
        case .repo(let repo):
            repoDetailView(repo: repo)
        }
    }

    // MARK: Active Workflows Detail

    private var activeWorkflowsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text("Active Workflows")
                    .font(.title2)
                    .fontWeight(.semibold)
                let count = viewModel.activeWorkflowCount
                if count > 0 {
                    Text("\(count)")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue))
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh")
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.5))

            Divider()

            if viewModel.activeWorkflows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("All clear — no active workflows")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Queued and in-progress runs will appear here")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.activeWorkflows) { active in
                        ActiveWorkflowRow(active: active)
                            .onTapGesture {
                                openWorkflowRun(active.run)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: Repo Detail

    private func repoDetailView(repo: GitHubRepo) -> some View {
        VStack(spacing: 0) {
            // Repo header
            HStack {
                Image(systemName: repo.private ? "lock" : "lock.open")
                    .foregroundStyle(.secondary)
                Text(repo.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                if let desc = repo.description, !desc.isEmpty {
                    Text("—")
                        .foregroundStyle(.tertiary)
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh")
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.5))

            Divider()

            // Workflow runs
            if viewModel.workflowRuns.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "play.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No workflow runs")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.workflowRuns) { run in
                        WorkflowRunRow(run: run)
                            .onTapGesture {
                                openWorkflowRun(run)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func openWorkflowRun(_ run: WorkflowRun) {
        guard let urlStr = run.htmlUrl, let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Active Workflow Row

struct ActiveWorkflowRow: View {
    let active: ActiveWorkflow

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: active.run.statusColor.icon)
                .font(.title3)
                .foregroundStyle(active.run.status == "in_progress" ? .blue : .yellow)
                .symbolEffect(.pulse, options: active.run.status == "in_progress" ? .repeating : .nonRepeating)

            VStack(alignment: .leading, spacing: 2) {
                // Repo + Workflow name
                HStack(spacing: 4) {
                    Text(active.repo.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Text(active.run.name ?? "Workflow")
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    // Branch
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(active.run.headBranch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Status badge
                    Text(active.run.statusColor.label)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(active.run.status == "in_progress" ? Color.blue : Color.yellow)
                        )

                    // Time
                    Text(active.run.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let _ = active.run.htmlUrl {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .cursor(.pointingHand)
    }
}

// MARK: - Repo Row

struct RepoRow: View {
    let repo: GitHubRepo
    @EnvironmentObject var viewModel: WorkflowViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            if let status = viewModel.latestStatus(for: repo) {
                Circle()
                    .fill(color(for: status))
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.body)
                    .lineLimit(1)
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Active run count
            let active = viewModel.activeRunCount(for: repo)
            if active > 0 {
                Text("\(active)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for status: WorkflowStatus) -> Color {
        switch status {
        case .queued: return .yellow
        case .inProgress: return .blue
        case .success: return .green
        case .failure: return .red
        case .cancelled, .skipped: return .gray
        case .timedOut: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Workflow Run Row

struct WorkflowRunRow: View {
    let run: WorkflowRun

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: run.statusColor.icon)
                .font(.title3)
                .foregroundStyle(run.statusColor == .inProgress ? .blue : color(for: run.statusColor))
                .symbolEffect(.pulse, options: run.status == "in_progress" ? .repeating : .nonRepeating)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.name ?? "Workflow")
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let event = run.event {
                        Text(event)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.controlBackgroundColor))
                            )
                    }
                }

                HStack(spacing: 8) {
                    // Branch
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(run.headBranch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Status badge
                    Text(run.statusColor.label)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(badgeColor(for: run.statusColor))
                        )

                    // Time
                    Text(run.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let _ = run.htmlUrl {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .cursor(.pointingHand)
    }

    private func color(for status: WorkflowStatus) -> Color {
        switch status {
        case .queued: return .yellow
        case .inProgress: return .blue
        case .success: return .green
        case .failure: return .red
        case .cancelled, .skipped: return .gray
        case .timedOut: return .orange
        case .unknown: return .gray
        }
    }

    private func badgeColor(for status: WorkflowStatus) -> Color {
        switch status {
        case .queued: return .yellow
        case .inProgress: return .blue
        case .success: return .green
        case .failure: return .red
        case .cancelled, .skipped: return .gray
        case .timedOut: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: WorkflowViewModel
    @State private var orgName: String = ""
    @State private var token: String = ""
    @State private var showToken = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text("GitTracker Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Organization")
                    .font(.headline)
                Text("The organization or user whose repos you want to track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. my-org", text: $orgName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Token")
                    .font(.headline)
                Text("A classic PAT or fine-grained token with `actions:read` and `repo` scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if showToken {
                        TextField("ghp_...", text: $token)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("ghp_...", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack {
                if !viewModel.orgName.isEmpty {
                    Button("Clear Settings") {
                        viewModel.clearSettings()
                        orgName = ""
                        token = ""
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") {
                    viewModel.showSettings = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save & Load") {
                    viewModel.saveSettings(org: orgName, token: token)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(orgName.isEmpty || token.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 340)
        .onAppear {
            orgName = viewModel.orgName
            token = viewModel.gitHubToken
        }
    }
}

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}
