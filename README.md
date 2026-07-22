# GitTracker — GitHub Actions Workflow Monitor

A native macOS app that tracks GitHub Actions workflow runs across all repos in an organization.

## Features

- **Org-wide view** — lists all repos in your org with live workflow status
- **Per-repo detail** — click any repo to see its recent workflow runs
- **Status badges** — color-coded: 🟢 success, 🔴 failure, 🔵 running, 🟡 queued
- **Auto-refresh** — polls every 15 seconds, no manual refreshing needed
- **Click to open** — click any run to open it in your browser
- **Secure token storage** — GitHub token stored in macOS Keychain
- **Settings** — configure org name and token from the UI

## Requirements

- macOS 14.0 (Sonoma) or later
- A GitHub token with `repo` and `actions:read` scopes
  - [Create a classic PAT here](https://github.com/settings/tokens)

## Build & Run

```bash
cd /Users/dipockdas/Projects/gittracker

# Build
make

# Build and launch
make run

# Clean
make clean
```

## Usage

1. Launch the app — the settings window opens automatically
2. Enter your GitHub org name (e.g. `Stealth-Micro-SaaS`)
3. Enter your GitHub token
4. Click **Save & Load**
5. Select a repo in the sidebar to see its workflow runs

## How It Works

- Uses the [GitHub REST API](https://docs.github.com/en/rest/actions/workflow-runs)
- Token stored in macOS Keychain via Security framework
- Auto-refreshes workflow runs every 15 seconds
- Repo list refreshes every 60 seconds
- Runs are sorted most-recent-first
