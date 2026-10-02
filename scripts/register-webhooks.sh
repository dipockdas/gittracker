#!/bin/bash
#
# Registers GitHub webhooks that point at the local receiver.
#
#   - one organisation-level hook per org in ORGS (covers every repo in it)
#   - one repository-level hook per repo listed in config/tracked-repos.txt
#
# Idempotent: existing hooks pointing at the same URL are left alone.
#
# Usage:
#   scripts/register-webhooks.sh [--dry-run]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$HOME/.config/gittracker"
SECRET_FILE="$CONFIG_DIR/webhook-secret"
URL_FILE="$CONFIG_DIR/webhook-url"
REPO_LIST="$ROOT/config/tracked-repos.txt"
ORG_LIST="$ROOT/config/tracked-orgs.txt"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'

info() { printf '%s==>%s %s\n' "$DIM" "$OFF" "$1"; }
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
skip() { printf '  %s·%s %s\n' "$DIM" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
err()  { printf '  %sx%s %s\n' "$RED" "$OFF" "$1"; }

command -v gh >/dev/null || { err "gh CLI not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { err "gh not authenticated — run: gh auth login"; exit 1; }

[ -f "$SECRET_FILE" ] || { err "missing $SECRET_FILE — run scripts/setup-tunnel.sh first"; exit 1; }
[ -f "$URL_FILE" ]    || { err "missing $URL_FILE — run scripts/setup-tunnel.sh first"; exit 1; }

SECRET="$(tr -d '[:space:]' < "$SECRET_FILE")"
WEBHOOK_URL="$(tr -d '[:space:]' < "$URL_FILE")"

[ -n "$SECRET" ]     || { err "webhook secret is empty"; exit 1; }
[ -n "$WEBHOOK_URL" ] || { err "webhook url is empty"; exit 1; }

if [ "$DRY_RUN" -eq 1 ]; then
  info "dry run — nothing will be created"
fi

info "target url: $WEBHOOK_URL"

SCOPES="$(gh auth status 2>&1 | grep -i 'Token scopes' || true)"
if [ -f "$ORG_LIST" ] && ! echo "$SCOPES" | grep -q 'admin:org_hook'; then
  warn "org-level hooks need the admin:org_hook scope, which this token lacks."
  warn "fix with:  gh auth refresh -h github.com -s admin:org_hook"
  warn "repo-level hooks below will still work."
  echo
fi

CREATED=0
SKIPPED=0
FAILED=0

register() {
  local api_path="$1" label="$2" body status existing stderr_file reason

  stderr_file="$(mktemp)"
  body="$(gh api "$api_path/hooks" 2>"$stderr_file")" && status=0 || status=$?

  if [ "$status" -ne 0 ]; then
    reason="$(grep -o 'This API operation needs.*' "$stderr_file" 2>/dev/null | head -1)"
    [ -n "$reason" ] || reason="$(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null)"
    rm -f "$stderr_file"
    err "$label — cannot read existing hooks: ${reason:-request failed}"
    printf '         left untouched; fix the above and re-run\n'
    FAILED=$((FAILED + 1))
    return 0
  fi
  rm -f "$stderr_file"

  existing="$(printf '%s' "$body" | jq --arg url "$WEBHOOK_URL" \
    '[.[] | select(.config.url == $url)] | length' 2>/dev/null || echo 0)"

  case "$existing" in
    ''|*[!0-9]*) err "$label — could not parse hook list"; FAILED=$((FAILED + 1)); return 0 ;;
  esac

  if [ "$existing" -gt 0 ]; then
    skip "$label — hook already registered"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    skip "$label — would create"
    return 0
  fi

  local response
  response="$(gh api --method POST "$api_path/hooks" --input - <<JSON 2>&1
{
  "name": "web",
  "active": true,
  "events": ["workflow_run"],
  "config": {
    "url": "$WEBHOOK_URL",
    "content_type": "json",
    "secret": "$SECRET",
    "insecure_ssl": "0"
  }
}
JSON
)" && status=0 || status=$?

  if [ "$status" -eq 0 ] && printf '%s' "$response" | jq -e '.id' >/dev/null 2>&1; then
    ok "$label"
    CREATED=$((CREATED + 1))
  else
    err "$label — $(printf '%s' "$response" | jq -r '.message // empty' 2>/dev/null || printf '%s' "$response" | head -c 160)"
    FAILED=$((FAILED + 1))
  fi
}

# --- Organisation-level hooks -------------------------------------------------

if [ -f "$ORG_LIST" ]; then
  info "organisations"
  while read -r org; do
    [ -z "$org" ] && continue
    case "$org" in \#*) continue ;; esac
    register "orgs/$org" "$org (all repos)"
  done < "$ORG_LIST"
fi

# --- Repository-level hooks ---------------------------------------------------

if [ -f "$REPO_LIST" ]; then
  info "repositories"
  count=0
  while read -r repo; do
    [ -z "$repo" ] && continue
    case "$repo" in \#*) continue ;; esac
    case "$repo" in */*) ;; *) warn "skipping '$repo' — expected owner/repo"; continue ;; esac
    register "repos/$repo" "$repo"
    count=$((count + 1))
  done < "$REPO_LIST"
  info "$count repo(s) considered"
fi

echo
info "summary: $CREATED created, $SKIPPED already present, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
  printf '\n%s%d hook(s) could not be registered — see the ✗ lines above.%s\n' "$YELLOW" "$FAILED" "$OFF"
  exit 1
fi
echo
info "verify with:"
printf '       gh api repos/OWNER/REPO/hooks --jq ".[].config.url"\n'
printf '       gh api orgs/ORG/hooks --jq ".[].config.url"\n'
