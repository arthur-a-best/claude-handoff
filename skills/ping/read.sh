#!/usr/bin/env bash
# Discord read — fetches reactions on the last ping (or a specific message).
#
# Usage:
#   read.sh                              # reads ~/.claude/state/last-ping-id
#   read.sh <message_id>                 # explicit message
#   read.sh --wait <max_seconds>         # poll until any reaction lands
#   read.sh <message_id> --wait 300      # poll specific message
#
# Output: one line per reaction emoji + count, e.g.
#   ✅ 1
#   ❌ 0
#   👍 2
#
# Exit code 0 = at least one reaction; 1 = no reactions; >=2 = error.
#
# WHY THIS WORKS WITH WEBHOOK-ONLY AUTH:
#   The Discord webhook URL grants enough perms to GET messages the webhook
#   itself sent (https://discord.com/api/webhooks/{id}/{token}/messages/{msg_id}).
#   That response includes the reactions array — so the operator can react
#   with ✅ / ❌ / 👍 / 🛑 / 🔁 etc. on the ping, and Claude polls reactions
#   to detect the answer. NO bot token, NO Gateway intents needed.
#
# CONVENTIONS (suggested — Claude can read any reactions):
#   ✅  approve / proceed
#   ❌  reject / abort
#   👍  yes / acknowledged
#   🛑  stop / hold
#   🔁  retry
#   👀  seen, no answer yet
#
# Dependencies: bash, curl, python (3 or 2). No jq.

set -euo pipefail

# ---- arg parse ----
MSG_ID=""
WAIT_SEC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)
      WAIT_SEC="${2:-60}"
      shift 2
      ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [ -z "$MSG_ID" ]; then
        MSG_ID="$1"
      else
        echo "unexpected arg: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$MSG_ID" ]; then
  STATE_FILE="${HOME}/.claude/state/last-ping-id"
  if [ -f "$STATE_FILE" ]; then
    MSG_ID=$(cat "$STATE_FILE")
  fi
fi
if [ -z "$MSG_ID" ]; then
  echo "no message_id (pass as arg, or run ping.sh first to capture it)" >&2
  exit 2
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "DISCORD_WEBHOOK_URL not set — see install.sh or ping.sh's setup notes" >&2
  exit 3
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
  echo "python is required" >&2
  exit 4
fi

URL="${DISCORD_WEBHOOK_URL}/messages/${MSG_ID}"

# Single fetch — extract reactions array
fetch_reactions() {
  local resp
  resp=$(curl -sS -w "\n%{http_code}" -X GET "$URL" -H "Content-Type: application/json")
  local code body
  code=$(printf '%s\n' "$resp" | tail -n1)
  body=$(printf '%s\n' "$resp" | sed '$d')
  if [ "$code" != "200" ]; then
    echo "fetch failed (HTTP $code): $body" >&2
    return 9
  fi
  printf '%s' "$body" | "$PYTHON" -c '
import json, sys
try:
    msg = json.load(sys.stdin)
except Exception as e:
    print("parse error:", e, file=sys.stderr)
    sys.exit(9)
reactions = msg.get("reactions") or []
if not reactions:
    sys.exit(1)  # no reactions yet
for r in reactions:
    emoji = (r.get("emoji") or {}).get("name", "?")
    count = r.get("count", 0)
    print(f"{emoji} {count}")
sys.exit(0)
'
}

# Polling vs one-shot
if [ "$WAIT_SEC" -gt 0 ]; then
  ELAPSED=0
  STEP=5
  while [ $ELAPSED -lt $WAIT_SEC ]; do
    if fetch_reactions; then
      exit 0
    fi
    sleep $STEP
    ELAPSED=$((ELAPSED + STEP))
  done
  echo "no reactions after ${WAIT_SEC}s" >&2
  exit 1
else
  fetch_reactions
fi
