#!/bin/bash
set -uo pipefail

PORT="${PORT:-8787}"
DB="${DB:-/tmp/gittracker-test/runs.sqlite}"
SECRET="test-secret-abc123"
SANDBOX="/tmp/gittracker-test/home"
SECRET_FILE="$SANDBOX/webhook-secret"
BIN="$(cd "$(dirname "$0")/.." && pwd)/.build/debug/gittracker-receiver"

rm -rf /tmp/gittracker-test && mkdir -p "$SANDBOX"

REAL_SECRET_BEFORE="$(cat "$HOME/.config/gittracker/webhook-secret" 2>/dev/null || echo none)"

GITTRACKER_PORT="$PORT" GITTRACKER_DB="$DB" GITTRACKER_WEBHOOK_SECRET="$SECRET" \
  GITTRACKER_SECRET_FILE="$SECRET_FILE" \
  "$BIN" > /tmp/gittracker-test/receiver.log 2>&1 &
RECEIVER_PID=$!
trap 'kill $RECEIVER_PID 2>/dev/null' EXIT

for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$PORT/health" > /dev/null 2>&1 && break
  sleep 0.25
done

pass=0
fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  \033[32mPASS\033[0m  %s\n" "$label"
    pass=$((pass + 1))
  else
    printf "  \033[31mFAIL\033[0m  %s (expected %s, got %s)\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

sign() {
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$SECRET" -r | cut -d' ' -f1
}

deliver() {
  local payload="$1" event="${2:-workflow_run}" signature="${3:-valid}"
  local header=""
  if [ "$signature" != "none" ]; then
    local digest="$signature"
    [ "$signature" = "valid" ] && digest="$(sign "$payload")"
    header="-H X-Hub-Signature-256:sha256=$digest"
  fi
  echo "$event" >> /tmp/gittracker-test/sent.log
  curl -s -o /tmp/gittracker-test/resp.json -w "%{http_code}" \
    -X POST "http://127.0.0.1:$PORT/webhook" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: $event" \
    -H "X-GitHub-Delivery: test-$RANDOM" \
    $header \
    --data-binary "$payload"
}

db() { sqlite3 "$DB" "$1"; }

RUNNING='{"action":"in_progress","repository":{"full_name":"Stealth-Micro-SaaS/geo-dashboard","name":"geo-dashboard","owner":{"login":"Stealth-Micro-SaaS"}},"sender":{"login":"dipockdas"},"workflow_run":{"id":11111,"name":"Deploy to Railway","head_branch":"main","head_sha":"abc123","status":"in_progress","conclusion":null,"workflow_id":777,"run_number":42,"event":"push","html_url":"https://github.com/Stealth-Micro-SaaS/geo-dashboard/actions/runs/11111","created_at":"2026-10-03T10:00:00Z","updated_at":"2026-10-03T10:00:05Z"}}'

COMPLETED='{"action":"completed","repository":{"full_name":"Stealth-Micro-SaaS/geo-dashboard","name":"geo-dashboard","owner":{"login":"Stealth-Micro-SaaS"}},"sender":{"login":"dipockdas"},"workflow_run":{"id":11111,"name":"Deploy to Railway","head_branch":"main","head_sha":"abc123","status":"completed","conclusion":"failure","workflow_id":777,"run_number":42,"event":"push","html_url":"https://github.com/Stealth-Micro-SaaS/geo-dashboard/actions/runs/11111","created_at":"2026-10-03T10:00:00Z","updated_at":"2026-10-03T10:04:00Z"}}'

echo "receiver end-to-end tests"
echo

echo "health endpoint"
check "GET /health returns 200" "200" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/health)"
check "reports secret configured" "true" "$(curl -s http://127.0.0.1:$PORT/health | jq -r .secretConfigured)"
check "unknown path is 404" "404" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/nope)"

echo
echo "signature enforcement"
check "valid signature accepted" "200" "$(deliver "$RUNNING" workflow_run valid)"
check "bad signature rejected" "401" "$(deliver "$RUNNING" workflow_run deadbeef)"
check "missing signature rejected" "401" "$(deliver "$RUNNING" workflow_run none)"
check "truncated signature rejected" "401" "$(deliver "$RUNNING" workflow_run "$(printf 'a%.0s' {1..64})")"

echo
echo "payload handling"
check "ping accepted so webhook registers" "200" "$(deliver '{"zen":"Keep it logically awesome."}' ping)"
check "unrelated event ignored, not failed" "200" "$(deliver '{"issue":{}}' issues)"
check "workflow_run without a run body accepted, not retried" "200" "$(deliver '{"action":"completed"}' workflow_run valid)"

echo
echo "storage"
check "run row written" "1" "$(db "SELECT COUNT(*) FROM runs WHERE run_id=11111;")"
check "repo captured" "Stealth-Micro-SaaS/geo-dashboard" "$(db "SELECT repo FROM runs WHERE run_id=11111;")"
check "status captured" "in_progress" "$(db "SELECT status FROM runs WHERE run_id=11111;")"
check "in_progress had no conclusion" "" "$(db "SELECT conclusion FROM runs WHERE run_id=11111;")"

deliver "$COMPLETED" workflow_run valid > /dev/null

check "completion updates in place, no duplicate row" "1" "$(db "SELECT COUNT(*) FROM runs WHERE run_id=11111;")"
check "status updated to completed" "completed" "$(db "SELECT status FROM runs WHERE run_id=11111;")"
check "conclusion captured" "failure" "$(db "SELECT conclusion FROM runs WHERE run_id=11111;")"
check "last_action updated" "completed" "$(db "SELECT last_action FROM runs WHERE run_id=11111;")"
check "created_at preserved from first sighting" "2026-10-03T10:00:00Z" "$(db "SELECT created_at FROM runs WHERE run_id=11111;")"

echo
echo "delivery audit log"
count() { db "SELECT COUNT(*) FROM deliveries WHERE outcome='$1';"; }

before=$(count stored)
deliver "$RUNNING" workflow_run valid > /dev/null
check "accepted delivery logged as stored" "1" "$(( $(count stored) - before ))"

before=$(count rejected_bad_signature)
deliver "$RUNNING" workflow_run deadbeef > /dev/null
check "wrong digest logged" "1" "$(( $(count rejected_bad_signature) - before ))"

before=$(count rejected_bad_signature)
deliver "$RUNNING" workflow_run "$(printf 'a%.0s' {1..64})" > /dev/null
check "right-length wrong digest logged as bad signature" "1" "$(( $(count rejected_bad_signature) - before ))"

before=$(count rejected_missing_signature)
deliver "$RUNNING" workflow_run none > /dev/null
check "absent signature logged" "1" "$(( $(count rejected_missing_signature) - before ))"

before=$(count no_workflow_run)
deliver '{"action":"completed"}' workflow_run valid > /dev/null
check "run-less payload logged, not stored" "1" "$(( $(count no_workflow_run) - before ))"

check "no rejected delivery ever became a run row" "0" \
  "$(db "SELECT COUNT(*) FROM runs WHERE run_id=999999;")"
check "distinct repos tracked" "1" "$(db "SELECT COUNT(DISTINCT repo) FROM runs;")"
check "no POST was dropped from the audit log" \
  "$(wc -l < /tmp/gittracker-test/sent.log | tr -d ' ')" \
  "$(db "SELECT COUNT(*) FROM deliveries;")"

echo
echo "no-secret behaviour"
GITTRACKER_PORT=$((PORT + 1)) GITTRACKER_DB=/tmp/gittracker-test/nosecret.sqlite \
  GITTRACKER_SECRET_FILE="$SANDBOX/does-not-exist" \
  "$BIN" > /tmp/gittracker-test/nosecret.log 2>&1 &
NOSECRET_PID=$!
for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$((PORT + 1))/health" > /dev/null 2>&1 && break
  sleep 0.25
done
check "unconfigured receiver refuses deliveries" "503" \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:$((PORT + 1))/webhook -H 'X-GitHub-Event: workflow_run' --data-binary "$RUNNING")"
check "unconfigured receiver reports no secret" "false" \
  "$(curl -s http://127.0.0.1:$((PORT + 1))/health | jq -r .secretConfigured)"
kill $NOSECRET_PID 2>/dev/null
wait $NOSECRET_PID 2>/dev/null

echo
echo "test isolation"
check "receiver never reads the real ~/.config secret" "absent" \
  "$([ -e "$SANDBOX/does-not-exist" ] && echo present || echo absent)"
check "real user secret file untouched by the suite" "$REAL_SECRET_BEFORE" \
  "$(cat "$HOME/.config/gittracker/webhook-secret" 2>/dev/null || echo none)"

echo
echo "-----------------------------------------"
printf "passed: %d   failed: %d\n" "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo; echo "receiver log:"; cat /tmp/gittracker-test/receiver.log; exit 1; }
