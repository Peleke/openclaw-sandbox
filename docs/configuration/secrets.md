# Secrets Management

Secrets management is the backbone of the sandbox's security posture. This page is the exhaustive reference for how secrets flow from your host machine into the VM, the gateway process, and sandbox containers -- without ever appearing in logs, process lists, or shell history.

![Secrets Pipeline](../diagrams/secrets-pipeline.svg)

## Three Injection Methods

The secrets role supports three sources, evaluated in strict priority order. The first source that provides any secret wins -- sources are not merged.

### 1. Direct Injection (highest priority)

Pass secrets as Ansible extra vars on the command line. Best for CI/CD pipelines and one-off testing.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "secrets_anthropic_api_key=sk-ant-xxx" \
  -e "secrets_gateway_password=mypass" \
  -e "secrets_github_token=ghp_xxx"
```

!!! warning "Shell history exposure"
    Direct injection puts secret values in your shell history. Use `secrets_skip=true` in CI/CD and inject via environment variables instead, or prefix the command with a space (if your shell is configured to ignore space-prefixed commands).

**When to use:** CI/CD pipelines, automated testing, quick iteration where you do not want a secrets file on disk.

### 2. Secrets File (recommended for development)

Create a `.env`-style file on your host and pass it via `--secrets`. This is the recommended approach for daily development.

```bash
# Create secrets file
cat > ~/.openclaw-secrets.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-api03-xxxxx
OPENAI_API_KEY=sk-xxxxx
GEMINI_API_KEY=AIzaSyxxxxx
OPENROUTER_API_KEY=sk-or-xxxxx
OPENCLAW_GATEWAY_PASSWORD=your-gateway-password
OPENCLAW_GATEWAY_TOKEN=your-gateway-token
GH_TOKEN=ghp_xxxxx
SLACK_BOT_TOKEN=xoxb-xxxxx
DISCORD_BOT_TOKEN=xxxxx
TELEGRAM_BOT_TOKEN=123456:ABC-xxxxx
EOF

# Lock down permissions on host
chmod 600 ~/.openclaw-secrets.env

# Bootstrap with secrets
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

The secrets file is mounted into the VM at `/mnt/secrets/<filename>` via Lima's virtiofs. Ansible reads it with `slurp`, base64-decodes it, and extracts each key using `regex_search`.

**When to use:** Day-to-day development. Keep one file, pass it every time.

### 3. Config Mount (existing OpenClaw users)

If you have an existing `~/.openclaw` directory with a `.env` file inside, mount the whole config directory.

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --config ~/.openclaw
```

Ansible looks for `.env` inside `/mnt/openclaw-config/` and extracts secrets from it using the same regex pipeline as method 2.

**When to use:** You already have a configured OpenClaw installation on your host and want to reuse its credentials.

## Priority Resolution

The secrets role evaluates sources in this order:

```
1. Check if any secrets_xxx variable is non-empty  --> "direct injection"
2. Check if mounted secrets file exists             --> "mounted secrets file"
3. Check if /mnt/openclaw-config/.env exists        --> "mounted config directory"
4. None matched                                     --> "none (no secrets configured)"
```

!!! note "No merging between sources"
    If you pass `-e "secrets_anthropic_api_key=sk-ant-xxx"` and also `--secrets ~/.secrets.env`, **only direct injection** is used. The secrets file is ignored entirely. The first source with any secret wins.

## Complete Variable Reference

### Secret Variables

| Ansible Variable | Env Var in `secrets.env` | Description | Used By |
|------------------|--------------------------|-------------|---------|
| `secrets_anthropic_api_key` | `ANTHROPIC_API_KEY` | Claude API key for LLM calls | Gateway, Cadence |
| `secrets_openai_api_key` | `OPENAI_API_KEY` | OpenAI API key | Gateway |
| `secrets_gemini_api_key` | `GEMINI_API_KEY` | Google Gemini API key | Gateway |
| `secrets_openrouter_api_key` | `OPENROUTER_API_KEY` | OpenRouter API key | Gateway |
| `secrets_gateway_password` | `OPENCLAW_GATEWAY_PASSWORD` | Password auth for gateway API | Gateway |
| `secrets_gateway_token` | `OPENCLAW_GATEWAY_TOKEN` | Token auth for gateway API | Gateway |
| `secrets_github_token` | `GH_TOKEN` | GitHub CLI token | Gateway, `gh` CLI, Sandbox containers |
| `secrets_slack_bot_token` | `SLACK_BOT_TOKEN` | Slack bot OAuth token | Gateway (Slack channel) |
| `secrets_discord_bot_token` | `DISCORD_BOT_TOKEN` | Discord bot token | Gateway (Discord channel) |
| `secrets_telegram_bot_token` | `TELEGRAM_BOT_TOKEN` | Telegram bot token | Gateway (Telegram channel) |

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `secrets_env_file` | `/etc/openclaw/secrets.env` | Output path for the generated secrets file |
| `secrets_env_file_mode` | `0600` | File permissions (owner read/write only) |
| `secrets_env_dir` | `/etc/openclaw` | Directory for secrets file |
| `secrets_env_dir_mode` | `0755` | Directory permissions |
| `secrets_mount_dir` | `/mnt/secrets` | Where `--secrets` file is mounted in VM |
| `secrets_filename` | `""` | Filename of the mounted secrets file (set by bootstrap) |
| `secrets_skip` | `false` | Skip secrets provisioning entirely |

## The Secrets Pipeline

### Step 1: Source Resolution

Ansible checks for direct variables first, then mounted files:

```yaml
# From ansible/roles/secrets/tasks/main.yml
has_direct_secrets: >-
  {{
    (secrets_anthropic_api_key | length > 0) or
    (secrets_openai_api_key | length > 0) or
    (secrets_gemini_api_key | length > 0) or
    ...
  }}
```

### Step 2: Extraction (for file-based sources)

For mounted files, Ansible reads the file content with `slurp` (base64), then uses `regex_search` to extract each key:

```yaml
# Extraction pattern for each secret
secrets_anthropic_api_key: >-
  {{ (mounted_secrets_content.content | b64decode
      | regex_search('ANTHROPIC_API_KEY=(.+)', '\\1'))
      | default([''], true) | first }}
```

!!! note "All extraction tasks use `no_log: true`"
    The `slurp`, `set_fact`, and extraction tasks are all marked `no_log: true`. Secret values never appear in Ansible output, even with `-vvv`.

### Step 3: Template Rendering

The secrets are rendered into `/etc/openclaw/secrets.env` using a Jinja2 template (`secrets.env.j2`):

```
# Only non-empty secrets are written
ANTHROPIC_API_KEY=sk-ant-xxx
GH_TOKEN=ghp_xxx
TELEGRAM_BOT_TOKEN=123456:ABC-xxx
```

The template conditionally includes each variable only if it has a value -- empty secrets are omitted entirely.

### Step 4: Gateway Consumption

The gateway systemd unit loads secrets via `EnvironmentFile=`:

```ini
# From the gateway service unit
EnvironmentFile=-/etc/openclaw/secrets.env
```

The `-` prefix means "don't fail if the file is missing." This makes the gateway start cleanly even without any secrets configured.

### Step 5: Sandbox Container Passthrough

For secrets that need to reach Docker containers (currently `GH_TOKEN`), the sandbox role adds an env passthrough to `openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "env": {
            "GH_TOKEN": "${GH_TOKEN}"
          }
        }
      }
    }
  }
}
```

The `${GH_TOKEN}` syntax tells OpenClaw to pass the gateway's `GH_TOKEN` environment variable into each sandbox container. The `gh` CLI natively respects `GH_TOKEN` -- no `gh auth login` is needed.

## Security Guarantees

### `no_log: true` on all secret-handling tasks

Every Ansible task that touches secret values -- `slurp`, `set_fact`, `template`, `copy` -- is marked `no_log: true`. Even running with maximum verbosity (`-vvv`) will not expose secret values in the Ansible output.

### File permissions: mode 0600

The secrets file at `/etc/openclaw/secrets.env` is created with `0600` permissions -- readable and writable only by the owner. The file is owned by the Ansible user (the VM's primary user).

```bash
# Verify permissions
limactl shell openclaw-sandbox -- ls -la /etc/openclaw/secrets.env
# -rw-------  1 <user> <user>  ... /etc/openclaw/secrets.env
```

### `EnvironmentFile=` vs `Environment=`

!!! danger "Why `EnvironmentFile=` matters"
    Using `Environment=` in a systemd unit puts secrets directly in the unit file and exposes them via `systemctl show`. Using `EnvironmentFile=` loads secrets from a file at service start -- they are not embedded in the unit file and are not visible via `systemctl show`. Both methods make values available in `/proc/<pid>/environ` (readable by root only), but `EnvironmentFile=` avoids the most common exposure vectors.

The gateway and cadence services both use:

```ini
EnvironmentFile=-/etc/openclaw/secrets.env
```

This means:

- Secrets are NOT visible in `systemctl show openclaw-gateway`
- Secrets are NOT visible in `ps auxe` or `/proc/<pid>/cmdline`
- Secrets ARE visible in `/proc/<pid>/environ` (to root only, which is expected)

### Never in process list

Because secrets are loaded via `EnvironmentFile=` (not passed as command-line arguments), they never appear in process listings. The `ExecStart=` line contains no secret values:

```ini
ExecStart=/usr/bin/node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
```

### Gateway gets Docker access without re-login

The gateway service uses `SupplementaryGroups=docker` in its systemd unit, giving it Docker access without requiring a user re-login or `newgrp`. This is a systemd feature -- supplementary groups take effect immediately for the service process.

## Sandbox Container Passthrough

The full flow for getting `GH_TOKEN` into sandbox containers:

```
Host secrets file
  --> Ansible regex extraction (no_log: true)
    --> /etc/openclaw/secrets.env (mode 0600)
      --> gateway EnvironmentFile= (loaded at service start)
        --> openclaw.json sandbox.docker.env.GH_TOKEN = "${GH_TOKEN}"
          --> Docker container (env var available to gh CLI)
```

The sandbox role checks whether `GH_TOKEN` exists in `secrets.env` before adding the passthrough:

```yaml
# From ansible/roles/sandbox/tasks/main.yml
- name: Check if GH_TOKEN is available in secrets
  ansible.builtin.command: grep -c '^GH_TOKEN=' /etc/openclaw/secrets.env
  register: gh_token_check

- name: Add GH_TOKEN env passthrough to sandbox config
  when: gh_token_check.rc == 0 and (gh_token_check.stdout | int) > 0
  # ... combine into openclaw.json
```

This means the passthrough is only configured when a token is actually present. No phantom env vars in containers.

## Adding a New Secret

To add support for a new secret (e.g., `MY_CUSTOM_TOKEN`), you need to modify **five locations** in the secrets role plus the template:

1. **`defaults/main.yml`** -- add `secrets_my_custom_token: ""`
2. **`tasks/main.yml` (extract from mounted file)** -- add regex extraction line for `MY_CUSTOM_TOKEN`
3. **`tasks/main.yml` (extract from config .env)** -- add regex extraction line (second copy)
4. **`tasks/main.yml` (has_direct_secrets)** -- add `(secrets_my_custom_token | length > 0) or`
5. **`tasks/main.yml` (has_any_secrets)** -- add `(secrets_my_custom_token | length > 0) or`
6. **`templates/secrets.env.j2`** -- add the conditional output block

## Troubleshooting

### Verify secrets are loaded

```bash
# Check which secrets are present (shows keys, not values)
limactl shell openclaw-sandbox -- sudo grep -c '=' /etc/openclaw/secrets.env

# See all secret keys (values redacted in this example)
limactl shell openclaw-sandbox -- sudo grep -oP '^[^=]+' /etc/openclaw/secrets.env
```

!!! tip "Viewing secret values"
    If you need to verify actual values (debugging auth failures), use:
    ```bash
    limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/secrets.env
    ```
    Only do this in a trusted terminal session.

### Check file permissions

```bash
# Should show -rw------- (0600)
limactl shell openclaw-sandbox -- ls -la /etc/openclaw/secrets.env
```

### Verify gateway loaded secrets

```bash
# Check gateway environment (look for key names, not values)
limactl shell openclaw-sandbox -- sudo systemctl show openclaw-gateway --property=EnvironmentFiles

# Check gateway is running
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway
```

### Verify GH_TOKEN in sandbox containers

```bash
# Check openclaw.json has the passthrough
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.env' ~/.openclaw/openclaw.json

# Test gh auth inside a sandbox container
limactl shell openclaw-sandbox -- docker run --rm \
  -e GH_TOKEN="$(sudo grep '^GH_TOKEN=' /etc/openclaw/secrets.env | cut -d= -f2)" \
  openclaw-sandbox:bookworm-slim gh auth status
```

### Token validity

```bash
# Test Anthropic key
limactl shell openclaw-sandbox -- bash -c \
  'source /etc/openclaw/secrets.env && curl -s -H "x-api-key: $ANTHROPIC_API_KEY" \
   -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models | head -c 200'

# Test GitHub token
limactl shell openclaw-sandbox -- bash -c \
  'source /etc/openclaw/secrets.env && gh auth status'
```

### Secrets provisioning was skipped

If you see "Secrets provisioning skipped" in Ansible output, check:

1. You did not pass `-e "secrets_skip=true"`
2. Your `--secrets` path exists and is readable
3. The file contains valid `KEY=VALUE` lines (no spaces around `=`)

### No secrets configured

If provisioning completes with "no secrets configured":

1. Check bootstrap output for the secrets source line
2. Verify your secrets file has the correct key names (e.g., `ANTHROPIC_API_KEY`, not `ANTHROPIC_KEY`)
3. Ensure values are not empty (e.g., `ANTHROPIC_API_KEY=` with nothing after `=` will be treated as empty)
