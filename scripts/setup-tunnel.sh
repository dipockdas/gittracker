#!/bin/bash
#
# Sets up a Cloudflare named tunnel that publishes the local GitTracker
# webhook receiver at https://hooks.<your-domain> -> http://127.0.0.1:8787
#
# Prerequisites:
#   - The domain's DNS is hosted by Cloudflare (Free plan is fine)
#   - cloudflared installed:  brew install cloudflared
#
# Usage:
#   scripts/setup-tunnel.sh your-domain.com
#
set -euo pipefail

DOMAIN="${1:-}"
TUNNEL_NAME="gittracker"
LOCAL_PORT="${GITTRACKER_PORT:-8787}"
CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"
PLIST="$HOME/Library/LaunchAgents/com.dipock.gittracker-tunnel.plist"
BIN="$(command -v cloudflared || true)"
RECEIVER_BIN="$(cd "$(dirname "$0")/.." && pwd)/.build/release/gittracker-receiver"

die() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$1"; }

[ -n "$DOMAIN" ] || die "usage: scripts/setup-tunnel.sh your-domain.com"
command -v gh >/dev/null || die "gh CLI not found"

if [ -z "$BIN" ]; then
  die "cloudflared not found. Install it with: brew install cloudflared"
fi

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_DIR/cert.pem" ]; then
  info "Authorising cloudflared with Cloudflare (opens a browser)"
  printf '    Choose the zone for %s when prompted.\n' "$DOMAIN"
  cloudflared tunnel login
else
  ok "already authorised (cert.pem present)"
fi

info "Checking for an existing '$TUNNEL_NAME' tunnel"
EXISTING_ID="$(cloudflared tunnel list --output json 2>/dev/null \
  | python3 -c "
import json,sys
try:
    tunnels = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in tunnels or []:
    if t.get('name') == '$TUNNEL_NAME':
        print(t['id']); break
" || true)"

if [ -n "$EXISTING_ID" ]; then
  TUNNEL_ID="$EXISTING_ID"
  ok "reusing tunnel $TUNNEL_ID"
else
  info "Creating tunnel '$TUNNEL_NAME'"
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_ID="$(cloudflared tunnel list --output json 2>/dev/null \
    | python3 -c "
import json,sys
for t in json.load(sys.stdin) or []:
    if t.get('name') == '$TUNNEL_NAME':
        print(t['id']); break
")"
  [ -n "$TUNNEL_ID" ] || die "could not determine new tunnel id"
  ok "created tunnel $TUNNEL_ID"
fi

HOSTNAME="hooks.$DOMAIN"
CREDENTIALS="$CONFIG_DIR/$TUNNEL_ID.json"
[ -f "$CREDENTIALS" ] || die "credentials file missing: $CREDENTIALS"

info "Writing tunnel config for $HOSTNAME"
cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS

ingress:
  - hostname: $HOSTNAME
    service: http://127.0.0.1:$LOCAL_PORT
  - service: http_status:404
EOF
ok "wrote $CONFIG_FILE"

info "Creating DNS route $HOSTNAME -> tunnel"
if cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" 2>&1 | grep -qi "already exists"; then
  ok "DNS record already exists"
else
  ok "DNS record created"
fi

info "Installing launchd agent"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.dipock.gittracker-tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>$CONFIG_FILE</string>
    <string>run</string>
    <string>$TUNNEL_NAME</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/gittracker-tunnel.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/gittracker-tunnel.err</string>
</dict>
</plist>
EOF

if [ ! -x "$RECEIVER_BIN" ]; then
  printf '\033[33m  warn\033[0m receiver binary missing — run: make receiver\n'
fi

launchctl bootout "gui/$(id -u)/com.dipock.gittracker-tunnel" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
ok "launchd agent loaded"

WEBHOOK_URL="https://$HOSTNAME/webhook"

info "Generating webhook secret if absent"
SECRET_FILE="$HOME/.config/gittracker/webhook-secret"
if [ ! -f "$SECRET_FILE" ]; then
  mkdir -p "$(dirname "$SECRET_FILE")"
  openssl rand -hex 32 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  ok "wrote $SECRET_FILE"
else
  ok "secret already exists at $SECRET_FILE"
fi

printf 'https://%s/webhook\n' "$HOSTNAME" > "$HOME/.config/gittracker/webhook-url"
chmod 600 "$HOME/.config/gittracker/webhook-url"
ok "wrote $HOME/.config/gittracker/webhook-url"

echo
printf '\033[32mtunnel ready\033[0m  %s  ->  http://127.0.0.1:%s\n' "$WEBHOOK_URL" "$LOCAL_PORT"
echo
echo "Next:"
echo "  1. make receiver && launchctl bootstrap gui/\$(id -u) \\"
echo "       ~/Library/LaunchAgents/com.dipock.gittracker-receiver.plist"
echo "  2. curl -s localhost:$LOCAL_PORT/health"
echo "  3. scripts/register-webhooks.sh    # register the hooks with GitHub"
echo
echo "Tunnel logs: tail -f ~/Library/Logs/gittracker-tunnel.err"
