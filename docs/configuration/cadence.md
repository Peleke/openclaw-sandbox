# Cadence Integration

[Cadence](https://github.com/Peleke/cadence) is typed event infrastructure for **ambient AI agency** -- agents that observe, notice, and act without being asked. Most AI agents are request-response: you ask, they answer. Cadence closes that gap by enabling agents that watch file changes, webhook events, and scheduled triggers, then act autonomously based on what they see.

In the sandbox, Cadence runs as a systemd service that watches your Obsidian vault, extracts insights from journal entries, and delivers digests to Telegram.

## What Cadence Does

```
Obsidian Watcher --> Insight Extractor (LLM) --> Insight Digest (Batching) --> Telegram Delivery
```

1. **Watches** your Obsidian vault for new or modified journal entries
2. **Extracts** insights using an LLM (Claude by default) from entries tagged with `::publish`
3. **Batches** insights into digests based on content pillars and schedule
4. **Delivers** digests to Telegram (or Discord, or a log file)

Under the hood, Cadence uses a pluggable architecture (Transport, Store, Executor) with type-safe signals. The sandbox integration uses the built-in file watcher source pointed at your Obsidian vault mount.

## Prerequisites

Cadence requires:

- An Obsidian vault mounted via `--vault`
- A Telegram bot token (for Telegram delivery)
- An Anthropic API key (for LLM extraction)

## Setup

### 1. Bootstrap with vault

```bash
# Using the Python CLI (recommended) — configure vault path during `sandbox init`
sandbox up

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --vault ~/Documents/Vaults/main \
  --secrets ~/.openclaw-secrets.env
```

Ensure your secrets file includes:

```
ANTHROPIC_API_KEY=sk-ant-xxx
TELEGRAM_BOT_TOKEN=123456:ABC-xxx
```

### 2. Configure cadence.json

The Ansible role creates a default `cadence.json` from a template. Edit it to set your Telegram chat ID and enable the pipeline:

```bash
limactl shell openclaw-sandbox -- nano ~/.openclaw/cadence.json
```

```json
{
  "enabled": true,
  "vaultPath": "/workspace-obsidian",
  "delivery": {
    "channel": "telegram",
    "telegramChatId": "YOUR_CHAT_ID",
    "fileLogPath": "~/.openclaw/cadence/signals.jsonl"
  },
  "pillars": [
    { "id": "tech", "name": "Technology", "keywords": ["code", "software", "ai", "engineering"] },
    { "id": "business", "name": "Business", "keywords": ["startup", "strategy", "growth"] },
    { "id": "life", "name": "Life", "keywords": ["reflection", "learning", "health"] }
  ],
  "llm": {
    "provider": "anthropic",
    "model": "claude-3-5-haiku-latest"
  },
  "extraction": {
    "publishTag": "::publish"
  },
  "digest": {
    "minToFlush": 3,
    "maxHoursBetween": 24,
    "cooldownHours": 2,
    "quietHoursStart": "22:00",
    "quietHoursEnd": "07:00"
  },
  "schedule": {
    "enabled": true,
    "nightlyDigest": "21:00",
    "morningStandup": "08:00",
    "timezone": "America/New_York"
  }
}
```

!!! tip "Getting your Telegram chat ID"
    Message your bot, then check: `curl https://api.telegram.org/bot<TOKEN>/getUpdates | jq '.result[0].message.chat.id'`

### 3. Restart the cadence service

```bash
limactl shell openclaw-sandbox -- sudo systemctl restart openclaw-cadence
```

## cadence.json Reference

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `false` | Master switch for the pipeline |
| `vaultPath` | `/workspace-obsidian` | Path to Obsidian vault inside VM (merged overlay mount) |
| `delivery.channel` | `telegram` | Delivery channel: `telegram`, `discord`, `log` |
| `delivery.telegramChatId` | `""` | Telegram chat ID for delivery |
| `delivery.fileLogPath` | `~/.openclaw/cadence/signals.jsonl` | JSONL log for container signal bridging |
| `pillars` | 3 default pillars | Content categories for insight classification |
| `llm.provider` | `anthropic` | LLM provider for extraction |
| `llm.model` | `claude-3-5-haiku-latest` | LLM model |
| `extraction.publishTag` | `::publish` | Tag that marks entries for extraction |
| `digest.minToFlush` | `3` | Minimum insights before sending a digest |
| `digest.maxHoursBetween` | `24` | Maximum hours between digests |
| `digest.cooldownHours` | `2` | Cooldown between digest deliveries |
| `digest.quietHoursStart` | `22:00` | Start of quiet hours (no delivery) |
| `digest.quietHoursEnd` | `07:00` | End of quiet hours |
| `schedule.enabled` | `true` | Enable scheduled digests |
| `schedule.nightlyDigest` | `21:00` | Time for nightly digest |
| `schedule.morningStandup` | `08:00` | Time for morning standup |
| `schedule.timezone` | `America/New_York` | Timezone for schedule |

## The `::publish` Marker

Write journal entries in your Obsidian vault with `::publish` on the second line (after the title) to mark them for insight extraction:

```markdown
# My Daily Journal Entry
::publish

Today I learned about OverlayFS and how it handles whiteout files...
```

Only entries with the `::publish` tag are processed by the extraction pipeline. Other entries are ignored.

## Vault Sync and the inotify Gotcha

Cadence watches the vault at `/workspace-obsidian` using chokidar (inotify under the hood). This is the **merged overlay mount** — not the raw upper directory.

!!! warning "Always write to the merged mount"
    Writing directly to the overlay upper dir (`/var/lib/openclaw/overlay/obsidian/upper/`) bypasses inotify on the merged mount. Cadence will never see those writes. Always write to `/workspace-obsidian/` so that file watchers detect the changes.

### Host-Side Vault Sync

If your Obsidian vault is synced via iCloud, virtiofs cannot read iCloud-locked files directly. The `sync-vault.sh` script uses rsync to copy vault contents to the VM:

```bash
# Manual sync
./scripts/sync-vault.sh

# Automated via launchd (see below)
```

The rsync uses `--exclude=.obsidian/` to avoid ESTALE errors on virtiofs lower-layer config files that iCloud may lock.

## Signal Bridging via fileLogPath

The `delivery.fileLogPath` field in cadence.json enables JSONL-based signal bridging. When set, cadence writes every signal event to this file in addition to the primary delivery channel:

```json
{
  "delivery": {
    "channel": "telegram",
    "fileLogPath": "~/.openclaw/cadence/signals.jsonl"
  }
}
```

This allows other processes (e.g., sandbox containers, buildlog, qortex) to read the signal log and react to cadence events without needing direct Telegram access.

## Custom Skills Mount

The `--skills` flag mounts a custom skills directory into the VM at `/mnt/skills-custom` (read-only):

```bash
# Using bootstrap.sh
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --vault ~/Documents/Vaults/main \
  --skills ~/Projects/skills/skills/custom

# The skills directory is available at /mnt/skills-custom inside the VM
```

Cadence can load custom skill definitions from this mount for use in the signal bus pipeline.

## Host-Side Scheduling (launchd)

Several launchd plist files in `scripts/` provide host-side scheduling for macOS. **These are manual installs** — bootstrap and Ansible provision the VM but do not modify your macOS LaunchAgents.

### Vault Sync (every 5 minutes)

`scripts/com.openclaw.vault-sync.plist` — runs `sync-vault.sh` on a timer to keep the VM vault current with host-side iCloud changes.

### Cadence Host Process

`scripts/com.openclaw.cadence.plist` — runs the cadence host-side coordinator.

### Dashboard Sync (every 10 minutes)

`scripts/com.openclaw.dashboard-sync.plist` — runs `dashboard-sync.sh` to pull GitHub issues into Obsidian kanban boards. See [Dashboard Sync](dashboard-sync.md) for full configuration.

### Installing the plists

```bash
# Copy whichever plists you want to automate
cp scripts/com.openclaw.vault-sync.plist ~/Library/LaunchAgents/
cp scripts/com.openclaw.cadence.plist ~/Library/LaunchAgents/
cp scripts/com.openclaw.dashboard-sync.plist ~/Library/LaunchAgents/

# Load them (starts immediately)
launchctl load ~/Library/LaunchAgents/com.openclaw.vault-sync.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.cadence.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.dashboard-sync.plist
```

!!! warning "Full Disk Access required"
    launchd agents cannot access `~/Documents/` without Full Disk Access (FDA) for `/bin/bash`. Grant FDA to `/bin/bash` in **System Settings > Privacy & Security > Full Disk Access**. Manual script runs from Terminal work fine because Terminal typically has FDA.

!!! note "Not handled by bootstrap"
    All host-side launchd plists are manual installs. Bootstrap provisions the **VM** via Ansible — it does not install macOS LaunchAgents. This is by design: host-side scheduling is a user choice, not a provisioning step.

## Ansible Variables

These variables can be set at bootstrap time with `-e`:

| Variable | Default | Description |
|----------|---------|-------------|
| `cadence_enabled` | `false` | Enable the cadence pipeline |
| `cadence_vault_path` | `/mnt/obsidian` | Vault path inside VM |
| `cadence_delivery_channel` | `telegram` | Delivery channel |
| `cadence_telegram_chat_id` | `""` | Telegram chat ID |
| `cadence_llm_provider` | `anthropic` | LLM provider |
| `cadence_llm_model` | `claude-3-5-haiku-latest` | LLM model |
| `cadence_schedule_enabled` | `true` | Enable scheduled digests |
| `cadence_nightly_digest` | `21:00` | Nightly digest time |
| `cadence_morning_standup` | `08:00` | Morning standup time |
| `cadence_timezone` | `America/New_York` | Schedule timezone |

Example:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --vault ~/Documents/Vaults/main \
  -e "cadence_enabled=true" \
  -e "cadence_telegram_chat_id=123456789"
```

## LLM Authentication

Cadence uses OpenClaw's `auth-profiles.json` for LLM access. During provisioning, if `ANTHROPIC_API_KEY` is found in `/etc/openclaw/secrets.env`, the cadence role creates:

```
~/.openclaw/agents/main/agent/auth-profiles.json
```

This file contains the API key reference for the LLM provider. The cadence service also loads secrets via `EnvironmentFile=-/etc/openclaw/secrets.env`.

!!! warning "No API key = no extraction"
    Without `ANTHROPIC_API_KEY` in your secrets, the LLM extraction step will not work. Cadence will still watch for file changes, but it cannot generate insights.

## Service Management

```bash
# Start cadence
limactl shell openclaw-sandbox -- sudo systemctl start openclaw-cadence

# Stop cadence
limactl shell openclaw-sandbox -- sudo systemctl stop openclaw-cadence

# Restart cadence (after config changes)
limactl shell openclaw-sandbox -- sudo systemctl restart openclaw-cadence

# Check status
limactl shell openclaw-sandbox -- sudo systemctl status openclaw-cadence

# View logs
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-cadence -f

# Manual digest trigger
limactl shell openclaw-sandbox -- bun /workspace/scripts/cadence.ts digest

# Run interactively (foreground, for debugging)
limactl shell openclaw-sandbox -- bun /workspace/scripts/cadence.ts start
```

## Systemd Service

The cadence service unit is deployed at `/etc/systemd/system/openclaw-cadence.service`:

- Runs as the Ansible user (not root)
- Loads secrets via `EnvironmentFile=-/etc/openclaw/secrets.env`
- Depends on `openclaw-gateway.service` and `workspace.mount` (if overlay is active)
- Restarts on failure with a 10-second delay

## Troubleshooting

### Cadence not starting

1. Check prerequisites: vault mounted, config exists, `enabled: true`
2. Check the service: `sudo systemctl status openclaw-cadence`
3. Check logs: `sudo journalctl -u openclaw-cadence --no-pager -n 50`

### No insights being extracted

1. Verify entries have `::publish` on line 2
2. Check `ANTHROPIC_API_KEY` is in secrets: `sudo grep ANTHROPIC_API_KEY /etc/openclaw/secrets.env`
3. Verify `auth-profiles.json` exists: `ls ~/.openclaw/agents/main/agent/auth-profiles.json`

### Digests not delivering to Telegram

1. Check `telegramChatId` in `cadence.json`
2. Verify `TELEGRAM_BOT_TOKEN` is in secrets
3. Check that `minToFlush` threshold is met (default: 3 insights before sending)
4. Check quiet hours -- no delivery between `22:00` and `07:00` by default
