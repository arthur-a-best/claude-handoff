#!/usr/bin/env bash
# Idempotent installer for the claude-handoff package.
#
# Usage:
#   bash install.sh                              # interactive — prompts for webhook URL
#   bash install.sh https://discord.com/...      # direct — pass webhook URL as arg
#   DISCORD_WEBHOOK_URL=https://... bash install.sh   # via env
#
# What it does:
#   1. Copies skills/ping/ to ~/.claude/skills/ping/  (cross-VS-Code: every
#      Claude Code session on this machine sees the skill)
#   2. Adds DISCORD_WEBHOOK_URL to ~/.claude/settings.json's env block
#      (preserves existing settings — never overwrites)
#   3. Sends a test ping to confirm the channel is reachable
#
# Dependencies: bash, curl, python (any of python3 / python / py).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SKILL_DIR="${CLAUDE_DIR}/skills/ping"
SETTINGS="${CLAUDE_DIR}/settings.json"

echo "→ claude-handoff installer"
echo "  source: ${SCRIPT_DIR}"
echo "  target: ${CLAUDE_DIR}"
echo ""

# 1. Resolve webhook URL — arg, then env, then prompt
WEBHOOK_URL="${1:-${DISCORD_WEBHOOK_URL:-}}"
if [ -z "$WEBHOOK_URL" ]; then
  echo "Discord webhook URL?"
  echo "  Get one: Discord → Server Settings → Integrations → Webhooks → New Webhook"
  read -r -p "URL: " WEBHOOK_URL
fi
if [ -z "$WEBHOOK_URL" ]; then
  echo "✗ no URL provided, aborting" >&2
  exit 1
fi
case "$WEBHOOK_URL" in
  https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*) ;;
  *)
    echo "✗ doesn't look like a Discord webhook URL: $WEBHOOK_URL" >&2
    echo "  expected: https://discord.com/api/webhooks/<id>/<token>" >&2
    exit 1
    ;;
esac

# 2. Pick a python interpreter (used both for settings.json merge + by ping.sh)
PYTHON=""
for cmd in python3 python py; do
  if command -v "$cmd" >/dev/null 2>&1; then
    PYTHON="$cmd"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "✗ python is required (python3, python, or py on PATH)" >&2
  exit 2
fi

# 3. Install the skill files
mkdir -p "$SKILL_DIR"
cp "${SCRIPT_DIR}/skills/ping/SKILL.md" "${SKILL_DIR}/SKILL.md"
cp "${SCRIPT_DIR}/skills/ping/ping.sh" "${SKILL_DIR}/ping.sh"
chmod +x "${SKILL_DIR}/ping.sh" 2>/dev/null || true
echo "✓ installed skill files to ${SKILL_DIR}"

# 4. Merge DISCORD_WEBHOOK_URL into settings.json (preserve existing config)
mkdir -p "$CLAUDE_DIR"
if [ ! -f "$SETTINGS" ]; then
  echo "{}" > "$SETTINGS"
fi

WEBHOOK_URL="$WEBHOOK_URL" SETTINGS="$SETTINGS" "$PYTHON" - <<'PY'
import json, os, sys
path = os.environ["SETTINGS"]
url = os.environ["WEBHOOK_URL"]
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
env = cfg.setdefault("env", {})
env["DISCORD_WEBHOOK_URL"] = url
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
echo "✓ wrote DISCORD_WEBHOOK_URL to ${SETTINGS}"

# 5. Test ping
echo ""
echo "→ sending test ping..."
if DISCORD_WEBHOOK_URL="$WEBHOOK_URL" bash "${SKILL_DIR}/ping.sh" \
    "✓ claude-handoff installed on $(hostname 2>/dev/null || echo this machine)" \
    "Skill at ${SKILL_DIR}. Restart Claude Code for the env block to take effect across new sessions; this machine is now reachable from any VS Code instance via the 'ping' skill."; then
  echo ""
  echo "✓ install complete. Check Discord for the test ping."
  echo "  Restart Claude Code so the env block is loaded into new sessions."
else
  echo ""
  echo "✗ test ping failed — verify the webhook URL is correct and try again." >&2
  exit 3
fi
