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
HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w "%{http_code}" \
  -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  --data-raw "$PAYLOAD")

if [ "$HTTP_CODE" = "204" ]; then
  echo "ping sent ($HTTP_CODE)"
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
