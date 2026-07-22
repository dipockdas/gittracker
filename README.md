# GitTracker

A native macOS app that monitors GitHub Actions workflow runs across every repo in your organization — all in one window.

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![MIT License](https://img.shields.io/badge/license-MIT-green)
[![GitHub](https://img.shields.io/badge/github-dipockdas%2Fgittracker-181717?logo=github)](https://github.com/dipockdas/gittracker)
[![CodeQL](https://github.com/dipockdas/gittracker/actions/workflows/codeql.yml/badge.svg)](https://github.com/dipockdas/gittracker/actions/workflows/codeql.yml)
[![SwiftLint](https://github.com/dipockdas/gittracker/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/dipockdas/gittracker/actions/workflows/swiftlint.yml)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-025E8C?logo=dependabot)](https://github.com/dipockdas/gittracker/security/dependabot)

## Features

- **Active Workflows dashboard** — a single list of every running or queued workflow across all repos, with repo name, branch, and status
- **Per-repo history** — click any repo to see its last 20 workflow runs
- **Color-coded status** — 🟢 success, 🔴 failure, 🔵 running, 🟡 queued
- **Auto-refresh** — polls every 15 seconds, no manual refreshing
- **Click to open** — click any run to jump to it in your browser
- **Secure token storage** — GitHub token stored in macOS Keychain, never on disk
- **Settings UI** — configure org name and token from the app

## Requirements

- macOS 14.0 (Sonoma) or later
- A GitHub token with `repo` and `actions:read` scopes
  - [Create a classic PAT](https://github.com/settings/tokens) or a fine-grained token with access to your org's repos

## Build & Run

```bash
git clone https://github.com/dipockdas/gittracker.git
cd gittracker

make        # build
make run    # build + launch
make clean  # clean build artifacts
```

Or open `Package.swift` in Xcode and run from there.

## Usage

1. Launch the app — the settings window opens automatically on first run
2. Enter your GitHub organization name (e.g. `my-org`)
3. Enter your GitHub token
4. Click **Save & Load**
5. The **Active Workflows** view opens by default — any running or queued jobs appear here
6. Click a repo in the sidebar to see its full workflow run history

## How It Works

- Uses the [GitHub REST API](https://docs.github.com/en/rest/actions/workflow-runs) (`GET /orgs/{org}/repos`, `GET /repos/{owner}/{repo}/actions/runs`)
- Token stored in macOS Keychain via the Security framework — never written to disk outside the Keychain
- Auto-refreshes workflow runs every 15 seconds
- All API calls run concurrently via `async`/`await` and `TaskGroup`
- Built with SwiftUI and Swift Package Manager — no Xcode project file needed

## Project Structure

```
Sources/
├── GitTrackerApp.swift       # App entry point
├── ContentView.swift         # Main UI (sidebar, active workflows, repo detail, settings)
├── WorkflowViewModel.swift   # State management, auto-refresh, data loading
├── GitHubService.swift       # GitHub REST API client
├── Models.swift              # Data models (WorkflowRun, GitHubRepo, ActiveWorkflow)
├── KeychainManager.swift     # Secure token storage wrapper
└── Resources/
    └── Info.plist            # App metadata
```

## License

MIT — see [LICENSE](LICENSE).
