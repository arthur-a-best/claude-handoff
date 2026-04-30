---
name: ping
description: Send a Discord ping to the operator from any Claude Code session, optionally read their reaction reply. Use when blocked on a decision the operator needs to make, when an autonomous task succeeds or fails, when long-running work completes, or when surfacing important findings the operator should see promptly. Webhook URL comes from the DISCORD_WEBHOOK_URL env var (set in ~/.claude/settings.json by install.sh). Bidirectional: ping.sh fires a Discord message; read.sh polls reactions on it (operator reacts with ✅ / ❌ / 👍 / 🛑 / 🔁 to reply asynchronously).
---

# Discord ping (and read)

Notify the operator via Discord webhook + read their reaction reply.
Cross-session, cross-project, cross-VS-Code-instance — works the same in
every Claude Code session because the credential lives at user level, not
in any repo.

## When to use this skill

Invoke proactively whenever:

- **Blocked** — you need a decision the operator must make. Don't wait
  silently; ping immediately so they can answer asynchronously by reacting.
- **Long task done** — autonomous deploy / build / migration finished.
  Ping with the outcome (✓ or ✗) and a one-line summary.
- **Surfacing a finding** — bug, security issue, or unexpected state.
- **Cost/risk gate** — about to take a hard-to-reverse action. Ping first,
  poll for ✅, then proceed. No reply within timeout = stop, don't proceed.

Do NOT use for:
- Routine progress chatter (Claude's main output stream is for that)
- Recoverable errors you're already retrying
- Anything you can resolve without the operator

## ping.sh — send a notification

```bash
bash ~/.claude/skills/ping/ping.sh "<title>" ["<optional context>"]
```

The first arg is the title (notification preview). The optional second
arg is a longer context block rendered as a Discord embed — use it for
stack traces, log excerpts, the failed command, etc.

The ping is sent with `?wait=true` so Discord returns the message ID,
which is persisted at `~/.claude/state/last-ping-id` for the companion
`read.sh` to use.

### Examples

```bash
# Decision needed
bash ~/.claude/skills/ping/ping.sh "Need decision: rollback or fix-forward?" \
  "Migration 0007 dropped a column. (A) restore backup, lose 12 min; (B) re-add nullable + backfill. React ✅ for A, 🔁 for B."

# Done
bash ~/.claude/skills/ping/ping.sh "✓ Cluster cutover complete" \
  "5 tenants migrated, 0 errors."

# Risky-action gate (poll for approval)
bash ~/.claude/skills/ping/ping.sh "About to git push --force, ack?" \
  "Reason: rebase to fix author email. React ✅ to proceed, ❌ to abort."
```

## read.sh — poll for the operator's reaction

```bash
bash ~/.claude/skills/ping/read.sh                    # last ping, one-shot
bash ~/.claude/skills/ping/read.sh --wait 300         # poll up to 5 minutes
bash ~/.claude/skills/ping/read.sh <message_id>       # specific message
```

Output: one line per reaction `<emoji> <count>`, e.g.
```
✅ 1
❌ 0
```

Exit codes:
- `0` — at least one reaction present
- `1` — no reactions (still waiting, or operator hasn't replied)
- `≥2` — error (no message_id, network, etc.)

### Suggested reaction conventions

The operator reacts with one of these emoji on the Discord ping. Claude
treats them as the answer:

| Emoji | Meaning |
|---|---|
| ✅ | approve / proceed |
| ❌ | reject / abort |
| 👍 | yes / acknowledged |
| 🛑 | stop / hold (don't proceed) |
| 🔁 | retry / try the other option |
| 👀 | seen, no answer yet |

Claude is free to add more conventions — read.sh just reports raw emoji
+ count and lets the calling logic decide what each means in context.

### Pattern: ping → wait → act

```bash
# Ping with the question
bash ~/.claude/skills/ping/ping.sh "Approve cluster destroy?" \
  "Will run: linode databases mysql delete <id>. Irreversible. React ✅ to proceed."

# Wait up to 10 minutes for any reaction
if bash ~/.claude/skills/ping/read.sh --wait 600 | grep -q "^✅"; then
  echo "approved, proceeding"
  # ... do the thing
elif bash ~/.claude/skills/ping/read.sh | grep -q "^❌"; then
  echo "rejected, aborting"
  exit 0
else
  echo "no answer in 10 min, defaulting to safe (no-op)"
  exit 0
fi
```

## Why this works with webhook-only auth

Discord webhooks normally only allow POST (write). But the same webhook
URL also permits `GET /messages/<message_id>` — it returns the full
message JSON including reactions. So the operator can react on the ping
with their phone's Discord app, and Claude reads the reactions back via
the same webhook URL — no Discord bot token, no Gateway intents, no
extra setup.

Limitation: this only reads reactions, not text replies. For text-reply
support you'd need a Discord bot with `MESSAGE_CONTENT` intent + a token
stored separately. Reactions cover ~95% of real "operator approves
A/B/cancel" decisions.

## Setup (one-time per machine)

If `DISCORD_WEBHOOK_URL` isn't set in `~/.claude/settings.json`, both
scripts print setup instructions instead of running. Run the package's
`install.sh` (or `install.ps1` on Windows) to wire it.
