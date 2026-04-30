---
name: ping
description: Send a Discord ping to the operator from any Claude Code session. Use when blocked on a decision the operator needs to make, when an autonomous task succeeds or fails, when long-running work completes, or when surfacing important findings the operator should see promptly. Webhook URL comes from the DISCORD_WEBHOOK_URL env var (set in ~/.claude/settings.json by install.sh).
---

# Discord ping

Notify the operator via Discord webhook. Cross-session, cross-project, cross-VS-Code-instance — works the same in every Claude Code session because the credential lives at user level, not in any repo.

## When to use this skill

Invoke proactively whenever:

- **Blocked** — you need a decision the operator must make ("two valid approaches, A vs B, which?"). Don't wait for the operator to come back; ping immediately so they can answer asynchronously.
- **Long task done** — autonomous deploy / build / migration finished. Ping with the outcome (✓ or ✗) and a one-line summary.
- **Surfacing a finding** — bug, security issue, or unexpected state that the operator should see *now* rather than next time they open the IDE.
- **Cost/risk gate** — about to take a hard-to-reverse action (force push, infra destroy, large API spend). Ping first, wait for ack, then proceed.

Do NOT use for:
- Routine progress chatter (Claude's main output stream is for that)
- Recoverable errors you're already retrying
- Anything you can resolve without the operator

## How to invoke

```bash
bash ~/.claude/skills/ping/ping.sh "<short message>" ["<optional context>"]
```

The first arg is the title (shown in the Discord notification preview). The optional second arg is a longer context block rendered as a Discord embed — use it for stack traces, log excerpts, the failed command, etc.

### Examples

```bash
# Decision needed
bash ~/.claude/skills/ping/ping.sh "Need decision: rollback or fix-forward?" \
  "Migration 0007 dropped a column on the prod tenant DB. Two options: (A) restore from backup taken 12 min ago, lose 12 min of writes; (B) re-add column nullable, backfill from audit log. Which?"

# Done
bash ~/.claude/skills/ping/ping.sh "✓ Cluster cutover complete" \
  "Django on aa-shared-mysql.servers.linodedb.net, 5 tenants migrated, 0 errors. Deploy log: <url>"

# Risky action gate
bash ~/.claude/skills/ping/ping.sh "About to git push --force to main, ack?" \
  "Reason: rebased 3 commits to fix author email. No content change. Reply 'go' or 'stop'."
```

## Setup (one-time per machine)

If `DISCORD_WEBHOOK_URL` isn't set in `~/.claude/settings.json`, this skill will print setup instructions instead of pinging. Run the package's `install.sh` to wire it.
