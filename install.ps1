# Idempotent installer for the claude-handoff package (PowerShell / Windows).
#
# Usage:
#   .\install.ps1                                       # interactive — prompts for webhook URL
#   .\install.ps1 -WebhookUrl "https://discord.com/..."  # direct
#   $env:DISCORD_WEBHOOK_URL="..."; .\install.ps1        # via env
#
# What it does:
#   1. Copies skills/ping/ to ~/.claude/skills/ping/
#   2. Adds DISCORD_WEBHOOK_URL to ~/.claude/settings.json's env block
#      (preserves existing settings, never overwrites)
#   3. Sends a test ping
#
# Dependencies: PowerShell 5.1+, python (any of py / python / python3 on PATH).

param(
    [string]$WebhookUrl = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SkillDir  = Join-Path $ClaudeDir "skills\ping"
$Settings  = Join-Path $ClaudeDir "settings.json"

Write-Host "-> claude-handoff installer"
Write-Host "   source: $ScriptDir"
Write-Host "   target: $ClaudeDir"
Write-Host ""

# 1. Resolve webhook URL
if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    if (-not [string]::IsNullOrWhiteSpace($env:DISCORD_WEBHOOK_URL)) {
        $WebhookUrl = $env:DISCORD_WEBHOOK_URL
    } else {
        Write-Host "Discord webhook URL?"
        Write-Host "  Get one: Discord -> Server Settings -> Integrations -> Webhooks -> New Webhook"
        $WebhookUrl = Read-Host "URL"
    }
}
if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
    Write-Error "no URL provided, aborting"
    exit 1
}
if ($WebhookUrl -notmatch "^https://discord(?:app)?\.com/api/webhooks/") {
    Write-Error "doesn't look like a Discord webhook URL: $WebhookUrl"
    exit 1
}

# 2. Pick a python interpreter
$Python = $null
foreach ($cmd in @("py", "python3", "python")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $Python = $cmd
        break
    }
}
if (-not $Python) {
    Write-Error "python is required (py, python, or python3 on PATH)"
    exit 2
}

# 3. Install the skill files
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
Copy-Item (Join-Path $ScriptDir "skills\ping\SKILL.md") (Join-Path $SkillDir "SKILL.md") -Force
Copy-Item (Join-Path $ScriptDir "skills\ping\ping.sh") (Join-Path $SkillDir "ping.sh") -Force
Write-Host "+ installed skill files to $SkillDir"

# 4. Merge DISCORD_WEBHOOK_URL into settings.json (preserve existing config)
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
if (-not (Test-Path $Settings)) {
    "{}" | Out-File -FilePath $Settings -Encoding utf8
}

$env:WEBHOOK_URL = $WebhookUrl
$env:SETTINGS = $Settings
& $Python -c @"
import json, os, sys
path = os.environ['SETTINGS']
url = os.environ['WEBHOOK_URL']
try:
    with open(path) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
env = cfg.setdefault('env', {})
env['DISCORD_WEBHOOK_URL'] = url
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
"@
if ($LASTEXITCODE -ne 0) {
    Write-Error "failed to write settings.json"
    exit 3
}
Write-Host "+ wrote DISCORD_WEBHOOK_URL to $Settings"

# 5. Test ping (need bash; on Windows: Git Bash or WSL)
Write-Host ""
Write-Host "-> sending test ping..."
$Bash = $null
foreach ($cmd in @("bash", "sh")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $Bash = $cmd
        break
    }
}
if (-not $Bash) {
    Write-Warning "bash not found on PATH — skill installed but couldn't run test ping. Install Git for Windows (https://git-scm.com/) and run:"
    Write-Warning "  bash $SkillDir\ping.sh `"test`""
    exit 0
}

$env:DISCORD_WEBHOOK_URL = $WebhookUrl
$pingPath = Join-Path $SkillDir "ping.sh"
& $Bash $pingPath `
    "+ claude-handoff installed on $env:COMPUTERNAME" `
    "Skill at $SkillDir. Restart Claude Code for the env block to take effect; this machine is now reachable from any VS Code instance via the 'ping' skill."

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "+ install complete. Check Discord for the test ping."
    Write-Host "  Restart Claude Code so the env block is loaded into new sessions."
} else {
    Write-Error "test ping failed (exit $LASTEXITCODE) — verify the webhook URL is correct"
    exit 4
}
