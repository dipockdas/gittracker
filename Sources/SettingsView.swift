import SwiftUI

private struct OrgDraft: Identifiable, Equatable {
    let id: UUID
    var login: String
    var token: String
    var loadAllRepositories: Bool
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: WorkflowViewModel
    @State private var drafts: [OrgDraft] = []
    @State private var selectedId: UUID?
    @State private var showToken = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                orgSidebar
                    .frame(width: 220)
                Divider()
                orgDetail
            }
            Divider()
            footer
        }
        .frame(width: 680, height: 440)
        .onAppear(perform: loadDrafts)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.blue)
                .font(.title2)
            Text("GitTracker Settings")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Sidebar

    private var orgSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Organizations")
                .font(.headline)
                .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(drafts) { draft in
                        orgRow(draft)
                    }
                }
                .padding(.vertical, 2)
            }

            Button(action: addOrganization) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.square.dashed")
                    Text("Add organization")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func orgRow(_ draft: OrgDraft) -> some View {
        let isSelected = draft.id == selectedId
        return Button {
            selectedId = draft.id
            showToken = false
            validationError = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(draft.login.isEmpty ? "New organization" : draft.login)
                    .foregroundStyle(draft.login.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var orgDetail: some View {
        if let index = drafts.firstIndex(where: { $0.id == selectedId }) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Organization")
                        .font(.headline)
                    Text("The organization or user whose repos you want to track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. my-org", text: $drafts[index].login)
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
                            TextField("ghp_...", text: $drafts[index].token)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("ghp_...", text: $drafts[index].token)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help(showToken ? "Hide token" : "Show token")
                    }
                }

                HStack {
                    Text("Load all repositories")
                        .font(.headline)
                    Spacer()
                    Toggle("Load all repositories", isOn: $drafts[index].loadAllRepositories)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if let validationError {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(20)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "building.2")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Select or add an organization")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Remove") {
                removeSelected()
            }
            .foregroundStyle(.red)
            .disabled(selectedId == nil)

            Spacer()

            Button("Cancel") {
                viewModel.showSettings = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Save changes") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private var persistableDrafts: [OrgDraft] {
        drafts.filter {
            !$0.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var canSave: Bool {
        if drafts.isEmpty { return true }

        let items = persistableDrafts
        guard !items.isEmpty else { return false }
        guard items.allSatisfy({
            !$0.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.token.isEmpty
        }) else { return false }

        let logins = items.map { $0.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return Set(logins).count == logins.count
    }

    private func loadDrafts() {
        drafts = viewModel.organizations.map {
            OrgDraft(
                id: $0.id,
                login: $0.login,
                token: viewModel.token(forOrgId: $0.id),
                loadAllRepositories: $0.loadAllRepositories
            )
        }
        if drafts.isEmpty {
            addOrganization()
        } else {
            selectedId = drafts.first?.id
        }
        showToken = false
        validationError = nil
    }

    private func addOrganization() {
        if let existing = drafts.first(where: { $0.login.isEmpty && $0.token.isEmpty }) {
            selectedId = existing.id
            return
        }
        let draft = OrgDraft(id: UUID(), login: "", token: "", loadAllRepositories: true)
        drafts.append(draft)
        selectedId = draft.id
        showToken = false
        validationError = nil
    }

    private func removeSelected() {
        guard let id = selectedId, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts.remove(at: index)
        if drafts.indices.contains(index) {
            selectedId = drafts[index].id
        } else {
            selectedId = drafts.last?.id
        }
        validationError = nil
    }

    private func save() {
        let items = persistableDrafts
        let logins = items.map { $0.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Set(logins).count != logins.count {
            validationError = "Each organization can only be added once."
            return
        }
        guard items.allSatisfy({
            !$0.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.token.isEmpty
        }) else {
            validationError = "Each organization needs a name and a token."
            return
        }

        let saved = items.map { draft in
            (
                TrackedOrg(
                    id: draft.id,
                    login: draft.login.trimmingCharacters(in: .whitespacesAndNewlines),
                    loadAllRepositories: draft.loadAllRepositories
                ),
                draft.token
            )
        }
        viewModel.saveOrganizations(saved)
    }
}
