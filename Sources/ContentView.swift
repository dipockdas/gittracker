import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: WorkflowViewModel

    private let compactBreakpoint: CGFloat = 600

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width < compactBreakpoint {
                    compactActiveWorkflowsView
                } else {
                    normalView
                }
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
        .onChange(of: viewModel.sidebarSelection) { _, selection in
            if case .repo(let repo) = selection {
                Task { await viewModel.ensureRunsLoaded(for: repo) }
            }
        }
        .task {
            if viewModel.hasConfiguration {
                await viewModel.loadRepos()
            }
        }
    }

    // MARK: - Normal Layout

    private var normalView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
    }

    // MARK: - Compact Layout

    private var compactActiveWorkflowsView: some View {
        activeWorkflowsView(compact: true)
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
            .padding(.vertical, 8)

            Divider()

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
                Text(viewModel.isLoading ? "Loading..." : "Auto-refresh \(viewModel.refreshIntervalSeconds)s")
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

                if viewModel.repos.isEmpty && !viewModel.isLoading {
                    Section("Repositories") {
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
                    }
                } else if viewModel.shouldGroupReposByOrg {
                    ForEach(viewModel.organizations) { org in
                        let orgRepos = viewModel.repos(for: org)
                        if !orgRepos.isEmpty {
                            Section(org.login) {
                                ForEach(orgRepos, id: \.self) { repo in
                                    RepoRow(repo: repo)
                                        .tag(SidebarSelection.repo(repo))
                                }
                            }
                        }
                    }
                } else {
                    Section("Repositories") {
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
        GeometryReader { geometry in
            switch viewModel.sidebarSelection {
            case .active:
                activeWorkflowsView(compact: geometry.size.width < compactBreakpoint)
            case .repo(let repo):
                repoDetailView(repo: repo, compact: geometry.size.width < compactBreakpoint)
            }
        }
    }

    // MARK: Active Workflows Detail

    private func activeWorkflowsView(compact: Bool) -> some View {
        VStack(spacing: 0) {
            workflowListHeader(compact: compact)

            if compact, let error = viewModel.errorMessage {
                compactErrorBanner(error)
            }

            Divider()

            if viewModel.displayedWorkflows.isEmpty {
                compactEmptyState(compact: compact)
            } else {
                List {
                    ForEach(viewModel.displayedWorkflows) { active in
                        ActiveWorkflowRow(
                            active: active,
                            compact: compact,
                            showOwner: viewModel.shouldGroupReposByOrg
                        )
                        .onTapGesture {
                            openWorkflowRun(active.run)
                        }
                        .listRowInsets(EdgeInsets(
                            top: compact ? 2 : 4,
                            leading: compact ? 8 : 12,
                            bottom: compact ? 2 : 4,
                            trailing: compact ? 8 : 12
                        ))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func workflowListHeader(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                    .font(compact ? .body : .title3)

                Text(compact ? viewModel.workflowListMode.title : "\(viewModel.workflowListMode.title) Workflows")
                    .font(compact ? .headline : .title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if viewModel.workflowListMode == .active, viewModel.activeWorkflowCount > 0 {
                    Text("\(viewModel.activeWorkflowCount)")
                        .font(compact ? .caption : .callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, compact ? 5 : 7)
                        .padding(.vertical, compact ? 1 : 2)
                        .background(Capsule().fill(Color.blue))
                }
            }

            Spacer(minLength: 4)

            Picker("Mode", selection: $viewModel.workflowListMode) {
                ForEach(WorkflowListMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(compact ? .small : .regular)
            .frame(width: compact ? 128 : 160)

            Spacer(minLength: 4)

            if compact {
                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(compact ? .body : .title3)
            }
            .disabled(viewModel.isLoading)
            .help("Refresh")
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    private func compactErrorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func compactEmptyState(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            Spacer()
            Image(systemName: viewModel.workflowListMode == .active ? "checkmark.circle" : "clock")
                .font(.system(size: compact ? 28 : 48))
                .foregroundStyle(viewModel.workflowListMode == .active ? .green : .secondary)
            Text(
                viewModel.workflowListMode == .active
                    ? "All clear — no active workflows"
                    : "No recent workflow runs"
            )
            .font(compact ? .callout : .title3)
            .foregroundStyle(.secondary)
            if !compact, viewModel.workflowListMode == .active {
                Text("Queued and in-progress runs will appear here")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    // MARK: Repo Detail

    private func repoDetailView(repo: GitHubRepo, compact: Bool = false) -> some View {
        VStack(spacing: 0) {
            // Repo header
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: repo.private ? "lock" : "lock.open")
                    .foregroundStyle(.secondary)
                    .font(compact ? .body : .title3)
                Text(viewModel.shouldGroupReposByOrg ? repo.fullName : repo.name)
                    .font(compact ? .headline : .title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if !compact, let desc = repo.description, !desc.isEmpty {
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
                        .font(compact ? .body : .title3)
                }
                .disabled(viewModel.isLoading)
                .help("Refresh")
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(Color(.windowBackgroundColor).opacity(0.5))

            Divider()

            let runs = viewModel.runs(for: repo)

            // Workflow runs
            if runs.isEmpty {
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
                    ForEach(runs) { run in
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
    var compact: Bool = false
    var showOwner: Bool = false

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            Image(systemName: active.run.statusColor.icon)
                .font(compact ? .caption : .body)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, options: active.run.status == "in_progress" ? .repeating : .nonRepeating)
                .fixedSize()

            Text(showOwner ? active.repo.fullName : active.repo.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Text(active.run.name ?? "Workflow")
                .font(compact ? .caption : .callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)

            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(active.run.headBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(0)

            Text(active.run.statusColor.label)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(badgeColor))
                .fixedSize()

            Text(active.run.relativeTime)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()

            if active.run.htmlUrl != nil {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.vertical, compact ? 1 : 3)
        .contentShape(Rectangle())
        .cursor(.pointingHand)
        .help(tooltip)
    }

    private var tooltip: String {
        let repo = showOwner ? active.repo.fullName : active.repo.name
        let name = active.run.name ?? "Workflow"
        return "\(repo) · \(name) · \(active.run.headBranch) · \(active.run.statusColor.label)"
    }

    private var iconColor: Color {
        switch active.run.statusColor {
        case .queued: return .yellow
        case .inProgress: return .blue
        case .success: return .green
        case .failure: return .red
        case .cancelled, .skipped: return .gray
        case .timedOut: return .orange
        case .unknown: return .gray
        }
    }

    private var badgeColor: Color {
        switch active.run.statusColor {
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
                    .truncationMode(.tail)
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                    .fixedSize()
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
                        .truncationMode(.tail)
                        .layoutPriority(2)

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
                            .layoutPriority(0)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    // Branch — lowest priority, truncates first
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(run.headBranch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(0)
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
                        .layoutPriority(2)
                        .fixedSize()

                    // Time
                    Text(run.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(2)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}
