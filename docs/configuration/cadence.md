# Cadence Integration

Cadence is the ambient AI pipeline that watches your Obsidian vault, extracts insights from journal entries, and delivers digests to Telegram. It runs as a systemd service inside the VM.

## What Cadence Does

```
Obsidian Watcher --> Insight Extractor (LLM) --> Insight Digest (Batching) --> Telegram Delivery
```

1. **Watches** your Obsidian vault for new or modified journal entries
2. **Extracts** insights using an LLM (Claude by default) from entries tagged with `::publish`
3. **Batches** insights into digests based on content pillars and schedule
4. **Delivers** digests to Telegram (or Discord, or a log file)

## Prerequisites

Cadence requires:

- An Obsidian vault mounted via `--vault`
- A Telegram bot token (for Telegram delivery)
- An Anthropic API key (for LLM extraction)

## Setup

### 1. Bootstrap with vault

```bash
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
  "vaultPath": "/mnt/obsidian",
  "delivery": {
    "channel": "telegram",
    "telegramChatId": "YOUR_CHAT_ID"
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
| `vaultPath` | `/mnt/obsidian` | Path to Obsidian vault inside VM |
| `delivery.channel` | `telegram` | Delivery channel: `telegram`, `discord`, `log` |
| `delivery.telegramChatId` | `""` | Telegram chat ID for delivery |
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
