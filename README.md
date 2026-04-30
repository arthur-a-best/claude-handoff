# claude-handoff

A user-level Claude Code skill that lets any session, in any VS Code instance,
on any machine, ping you on Discord when it needs direction or wants to
surface something you should see.

The skill installs to `~/.claude/skills/ping/` (user-scope, not per-repo) so
**every Claude Code session everywhere on the machine** can use it. The
Discord webhook URL is stored in `~/.claude/settings.json`'s `env` block —
loaded once on session start, available to every Bash tool call.

## What it solves

- You start a long task with Claude in VS Code. You walk away.
- Claude hits a fork: needs you to pick A or B before continuing.
- Without this skill, Claude stops and waits silently in the IDE — you
  don't know.
- With this skill: Claude calls `bash ~/.claude/skills/ping/ping.sh
  "Decision needed: A or B?" "<context>"`. Your phone buzzes. You decide
  asynchronously. Next session reads your reply.

## Install (any machine, ~60 seconds)

### 1. Get a Discord webhook

In Discord:
- **Server Settings** → **Integrations** → **Webhooks** → **New Webhook**
- Pick the channel you want pings in (e.g. `#claude`)
- **Copy Webhook URL** — looks like `https://discord.com/api/webhooks/<id>/<token>`

### 2. Run the installer

```bash
# macOS / Linux / Windows-with-Git-Bash:
git clone <this repo> claude-handoff
cd claude-handoff
bash install.sh

# Windows (PowerShell):
git clone <this repo> claude-handoff
cd claude-handoff
.\install.ps1
```

The installer:
1. Copies the skill files to `~/.claude/skills/ping/`
2. Adds `DISCORD_WEBHOOK_URL` to your `~/.claude/settings.json`'s `env`
   block (merges with existing config — never overwrites)
3. Sends a test ping to confirm the channel is reachable

### 3. Restart Claude Code

The `env` block is loaded on session start. After restart, every
session in every VS Code instance has `$DISCORD_WEBHOOK_URL` set
automatically.

## Use from Claude

In any Claude Code session, when you'd want to be alerted:

```bash
bash ~/.claude/skills/ping/ping.sh "<title>" "<optional context>"
```

The skill is also discoverable via Claude's `Skill` tool — invoking
`Skill ping` will pull up the SKILL.md instructions.

### Examples

```bash
# Decision needed
bash ~/.claude/skills/ping/ping.sh "Need decision: rollback or fix-forward?" \
  "Migration 0007 dropped a column. Options: (A) restore backup; (B) re-add nullable + backfill from audit log."

# Long task done
bash ~/.claude/skills/ping/ping.sh "✓ Cluster cutover complete" \
  "Django on cluster, 5 tenants migrated, 0 errors."

# Risky action gate
bash ~/.claude/skills/ping/ping.sh "About to git push --force, ack?" \
  "Reason: rebase to fix author email. No content change."
```

The Discord embed footer shows hostname, timestamp, and (if cwd is a git
checkout) the repo + branch + short SHA — so you can tell which project
the ping came from at a glance.

## What's in the box

```
claude-handoff/
├── README.md          (this file)
├── install.sh         (Linux/macOS/Git-Bash installer)
├── install.ps1        (Windows PowerShell installer)
└── skills/
    └── ping/
        ├── SKILL.md   (Claude reads this to know when to invoke)
        └── ping.sh    (the actual webhook caller)
```

## Notes

- **One-way.** Claude pings you; you reply asynchronously via Discord
  (which Claude doesn't read). To bridge the other direction, you'd
  reply on a GitHub issue or send Claude a follow-up prompt next session.
- **Per-machine.** The webhook URL is stored in the per-machine
  `~/.claude/settings.json`. Each laptop / each user account installs
  separately. (You can use the same webhook URL on every machine — they'll
  all post to the same Discord channel — or use different channels per
  machine.)
- **Cross-VS-Code-instance.** Once installed, every Claude Code session
  in every VS Code window on this machine can invoke the skill. No
  per-repo config.
- **Dependencies.** `bash`, `curl`, `python` (3 or 2). All available by
  default on macOS/Linux. On Windows: Git for Windows ships bash + curl;
  Python typically needs explicit install.

## Uninstall

```bash
rm -rf ~/.claude/skills/ping
# Then manually remove "DISCORD_WEBHOOK_URL" from ~/.claude/settings.json's env block
```
