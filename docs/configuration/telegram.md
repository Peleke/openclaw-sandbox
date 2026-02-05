# Telegram Integration

The sandbox supports Telegram bot integration with **pairing-based access control**. There is no open access by default -- unknown senders must go through a pairing flow before they can message the agent.

## Setup

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow the prompts
3. Copy the bot token (format: `123456:ABC-xxxxx`)

### 2. Get Your Telegram User ID

Message [@userinfobot](https://t.me/userinfobot) on Telegram. It will reply with your numeric user ID.

### 3. Add Token to Secrets

Add your bot token to your secrets file:

```bash
echo 'TELEGRAM_BOT_TOKEN=123456:ABC-xxxxx' >> ~/.openclaw-secrets.env
```

### 4. Bootstrap with Pre-Approved User ID

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  --secrets ~/.openclaw-secrets.env \
  -e "telegram_user_id=YOUR_TELEGRAM_ID"
```

!!! tip "Pre-seeding your user ID"
    The `-e "telegram_user_id=..."` flag pre-approves your Telegram account so you can message the bot immediately after bootstrap. Without it, you would need to approve your own pairing code -- which requires access to the VM.

## Access Control: Pairing-Based Security

The sandbox sets `dmPolicy: "pairing"` in the OpenClaw configuration. This is enforced during the `fix-vm-paths.yml` task in the gateway role, which updates `openclaw.json` if a `channels.telegram` section already exists:

!!! note "Requires existing Telegram config"
    The `dmPolicy` and `allowFrom` settings are only written if `channels.telegram` is already defined in `openclaw.json`. If you are using `--config` to mount an existing host config that has Telegram configured, this works automatically. If you create a fresh config (no `--config` flag), you may need to add the `channels.telegram` section manually or via `--onboard`.

```json
{
  "channels": {
    "telegram": {
      "dmPolicy": "pairing",
      "allowFrom": ["YOUR_TELEGRAM_ID"]
    }
  }
}
```

### How Pairing Works

| Scenario | What Happens |
|----------|-------------|
| **Your ID is pre-seeded** (`-e telegram_user_id=...`) | You can message the bot immediately |
| **Unknown sender messages the bot** | Bot responds with a pairing code |
| **Owner approves the pairing code** | Sender is added to the allow list |
| **Approved sender messages the bot** | Normal agent interaction |

### Approving Pairing Codes

When someone new messages the bot, they receive a pairing code. Approve it from the host:

```bash
# Approve a pairing code
limactl shell openclaw-sandbox -- claw pair approve <CODE>

# List pending pairing requests
limactl shell openclaw-sandbox -- claw pair list
```

!!! warning "Without pre-seeding"
    If you bootstrap without `-e "telegram_user_id=..."`, even you (the owner) will receive a pairing code when you first message the bot. You will need to approve it via the VM CLI.

## Configuration

The Telegram bot token is managed through the [secrets pipeline](secrets.md). The access control settings are written to `openclaw.json` during gateway provisioning.

| Setting | Location | Value |
|---------|----------|-------|
| Bot token | `/etc/openclaw/secrets.env` | `TELEGRAM_BOT_TOKEN=...` |
| DM policy | `~/.openclaw/openclaw.json` | `channels.telegram.dmPolicy: "pairing"` |
| Allow list | `~/.openclaw/openclaw.json` | `channels.telegram.allowFrom: [...]` |

### Changing Access Control

To modify the allow list after bootstrap, edit `openclaw.json` directly:

```bash
# Edit config
limactl shell openclaw-sandbox -- nano ~/.openclaw/openclaw.json

# Restart gateway to pick up changes
limactl shell openclaw-sandbox -- sudo systemctl restart openclaw-gateway
```

## Verification Commands

```bash
# Check gateway is running
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway

# Check bot status
limactl shell openclaw-sandbox -- claw status

# View Telegram-specific logs
limactl shell openclaw-sandbox -- tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | grep telegram

# Check Telegram config in openclaw.json
limactl shell openclaw-sandbox -- jq '.channels.telegram' ~/.openclaw/openclaw.json

# Verify bot token is loaded (key presence only)
limactl shell openclaw-sandbox -- sudo grep -c 'TELEGRAM_BOT_TOKEN' /etc/openclaw/secrets.env
```

## Troubleshooting

### Bot not responding

1. Check the gateway is running: `systemctl status openclaw-gateway`
2. Check the bot token is in secrets: `sudo grep TELEGRAM_BOT_TOKEN /etc/openclaw/secrets.env`
3. Check gateway logs for Telegram errors: `sudo journalctl -u openclaw-gateway -f`

### Pairing code not appearing

1. Verify `dmPolicy` is set to `"pairing"` in `openclaw.json`
2. Check that the sender is not already in `allowFrom`
3. Look at gateway logs for the pairing attempt

### Cannot approve pairing code

1. Ensure you are running `claw pair approve <CODE>` from within the VM (via `limactl shell`)
2. Check that the gateway is running and accessible
