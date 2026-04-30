#!/usr/bin/env bash
# Discord ping — fires a webhook POST to DISCORD_WEBHOOK_URL.
#
# Usage:
#   ping.sh "<title>" ["<optional context>"]
#
# Reads DISCORD_WEBHOOK_URL from the environment (set by Claude Code from
# ~/.claude/settings.json's `env` block). If unset, prints setup instructions
# and exits 2 (Claude can detect the failure and prompt the operator).
#
# Dependencies: bash, curl, python (3 or 2). No jq, since jq isn't available
# by default on Windows / fresh machines.

set -euo pipefail

TITLE="${1:-}"
CONTEXT="${2:-}"

if [ -z "$TITLE" ]; then
  echo "usage: ping.sh \"<title>\" [\"<context>\"]" >&2
  exit 1
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  cat >&2 <<EOF
DISCORD_WEBHOOK_URL is not set.

Setup (one-time, per machine):
  1. In Discord: Server Settings → Integrations → Webhooks → New Webhook
     Pick a channel, copy the webhook URL.
  2. Run install.sh (or install.ps1 on Windows) from the claude-handoff
     package, OR manually add to ~/.claude/settings.json:

       {
         "env": { "DISCORD_WEBHOOK_URL": "<your URL>" }
       }

  3. Restart Claude Code (env block is read on session start).
EOF
  exit 2
fi

# Pick a python interpreter
PYTHON=""
for cmd in python3 python py; do
  if command -v $cmd >/dev/null 2>&1; then
    PYTHON=$cmd
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "python is required (python3, python, or py on PATH)." >&2
  exit 3
fi

# Hostname + timestamp + repo (if cwd is a git checkout) for the embed footer
HOST="$(hostname 2>/dev/null || echo unknown)"
TS="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
REPO=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  SHA="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
  REPO=" · ${REPO_NAME}@${BRANCH} (${SHA})"
fi
FOOTER="${HOST} · ${TS}${REPO}"

# Build JSON via python — handles quoting/control chars safely.
# Discord limits: content ≤ 2000 chars, embed.description ≤ 4096 chars.
PAYLOAD=$(TITLE="$TITLE" CONTEXT="$CONTEXT" FOOTER="$FOOTER" "$PYTHON" -c '
import json, os
title = os.environ.get("TITLE", "")[:1900]
ctx = os.environ.get("CONTEXT", "")[:3900]
footer = os.environ.get("FOOTER", "")
embed = {"footer": {"text": footer}}
if ctx:
    embed["description"] = ctx
print(json.dumps({"content": title, "embeds": [embed]}))
')

RESP_FILE=$(mktemp 2>/dev/null || echo "/tmp/discord_resp.$$")

# ?wait=true makes Discord return the created message JSON (200) instead of
# acking with 204. We need that to capture the message ID — without it,
# read.sh can't poll for reactions on the ping.
WEBHOOK_URL_WITH_WAIT="${DISCORD_WEBHOOK_URL}?wait=true"
HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w "%{http_code}" \
  -X POST "$WEBHOOK_URL_WITH_WAIT" \
  -H "Content-Type: application/json" \
  --data-raw "$PAYLOAD")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
  # Persist message ID so read.sh can poll for reactions later
  if [ "$HTTP_CODE" = "200" ]; then
    # Pipe via stdin (avoids /tmp path translation on Git Bash/Windows where
    # python is native Windows and can't see MSYS-mapped Unix paths).
    MSG_ID=$(cat "$RESP_FILE" | "$PYTHON" -c "
import json, sys
try:
    print(json.load(sys.stdin).get('id', ''))
except Exception:
    pass
" 2>/dev/null)
    if [ -n "$MSG_ID" ]; then
      STATE_DIR="${HOME}/.claude/state"
      mkdir -p "$STATE_DIR" 2>/dev/null
      echo "$MSG_ID" > "$STATE_DIR/last-ping-id" 2>/dev/null
      echo "ping sent (HTTP $HTTP_CODE, message_id=$MSG_ID)"
    else
      echo "ping sent (HTTP $HTTP_CODE) but no message_id parsed"
    fi
  else
    echo "ping sent ($HTTP_CODE — no body, reactions can't be read)"
  fi
  rm -f "$RESP_FILE"
  exit 0
elif [ "$HTTP_CODE" = "429" ]; then
  echo "rate-limited; Discord said: $(cat "$RESP_FILE" 2>/dev/null)" >&2
  rm -f "$RESP_FILE"
  exit 4
else
  echo "ping failed (HTTP $HTTP_CODE): $(cat "$RESP_FILE" 2>/dev/null)" >&2
  rm -f "$RESP_FILE"
  exit 5
fi
