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

make              # build
make run          # build + launch
make clean        # clean build artifacts
make receiver     # build the webhook receiver daemon
make receiver-test  # run the receiver test suite
```

Or open `Package.swift` in Xcode and run from there.

## Webhook Receiver

Polling the REST API does not scale past a few dozen repositories: at 60s
intervals, 300 repos needs ~18,000 requests/hour against a 5,000/hour limit.
The receiver inverts that — GitHub *pushes* `workflow_run` events to a local
daemon, so status arrives within a second and costs no API budget at all.

- **`gittracker-receiver`** — a standalone Swift executable listening on
  `127.0.0.1:8787`. Verifies `X-Hub-Signature-256` (HMAC-SHA256, constant-time),
  then writes to SQLite in WAL mode. No third-party dependencies; `Network`
  framework and `CryptoKit` only.
- **Two tables.** `runs` holds the latest state per repo, upserted in place as a
  run progresses. `deliveries` is an audit log of every POST including
  rejections, so "did the webhook fire?" is a query rather than a guess.
- **Fails closed.** With no secret configured it returns `503` and stores
  nothing, so the database cannot be poisoned while unprotected.

The database is the contract between the daemon and the app — they share no
Swift types, so a refactor on either side cannot break the other.

### Setup

```bash
brew install cloudflared
scripts/setup-tunnel.sh your-domain.com     # tunnel, DNS route, launchd, secret
make receiver
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/com.dipock.gittracker-receiver.plist

gh auth refresh -h github.com -s admin:org_hook   # only needed for org-level hooks
scripts/register-webhooks.sh --dry-run             # inspect
scripts/register-webhooks.sh                       # create
```

`scripts/setup-tunnel.sh` publishes `https://hooks.<domain>` to the local
receiver using a Cloudflare named tunnel (free, unmetered, stable hostname).
`scripts/register-webhooks.sh` is idempotent: it reads `config/tracked-orgs.txt`
(one org-level hook each, covering every repo in the org) and
`config/tracked-repos.txt` (a hook per repo, since GitHub has no user-level
webhook). Re-run it after editing either list.

Note that the receiver only records events while the tunnel is running, and
webhooks only fire for activity after registration — keep a slow poll running
for reconciliation and backfill.

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
├── SettingsView.swift        # Multi-organization settings UI
└── Resources/
    └── Info.plist            # App metadata

Receiver/
├── main.swift                # Routing, ping handling, signature gate
├── HTTPServer.swift          # HTTP/1.1 over the Network framework
├── WebhookVerifier.swift     # HMAC-SHA256 signature check
├── WebhookEvent.swift        # workflow_run payload decoding
├── RunStore.swift            # SQLite persistence (runs + delivery audit log)
└── test-receiver.sh          # End-to-end test suite
```

## License

MIT — see [LICENSE](LICENSE).
