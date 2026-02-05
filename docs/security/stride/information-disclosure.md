# Information Disclosure

Information disclosure means data ends up somewhere it shouldn't. In OpenClaw's case, the interesting data is API keys, journal/vault contents, and system internals. The system handles secrets at multiple layers -- host mounts, Ansible provisioning, systemd services -- and each transition is a place things can leak.

The secrets pipeline is actually one of the better-defended parts of the sandbox. The gaps are mostly at the application layer.

## Threat Inventory

| ID | Threat | Risk | Notes |
|----|--------|------|-------|
| I-1 | API keys leak via Ansible logs, journald, or process lists | Low | Mitigated -- `no_log: true` on all secret-handling tasks, `EnvironmentFile=` instead of `Environment=` |
| I-2 | Journal/vault contents exposed via Telegram | Medium | Pairing mode restricts who can talk to the bot, but Telegram servers still see message content |
| I-3 | Prompt injection extracts secrets from LLM context | Medium | No output filtering -- if the agent has access to a secret and gets tricked, it can echo it |
| I-4 | Error messages reveal internal paths or config | Low | Gateway runs inside VM, so path disclosure has limited value |
| I-5 | Secrets committed to git history | Low | Mitigated -- sync-gate runs gitleaks before changes reach host |
| I-6 | Mount points expose host data to compromised VM | Medium | `/mnt/openclaw` is writable, `/mnt/secrets` is read-only but readable by any VM process |

## What We Actually Have

**Secrets pipeline (`ansible/roles/secrets/`).** This is the most thoroughly hardened part of the system. Every Ansible task that touches secret values uses `no_log: true` (7+ occurrences in `tasks/main.yml`). The generated `secrets.env` file is mode `0600`, owned by the service user.

**`EnvironmentFile=` not `Environment=`.** The gateway and cadence systemd units load secrets via `EnvironmentFile=-/etc/openclaw/secrets.env`. This keeps secrets out of `/proc/PID/environ` and `ps aux` output. The `-` prefix means the service still starts if the file is missing.

```ini
# From the gateway systemd unit
EnvironmentFile=-/etc/openclaw/secrets.env
```

**UFW egress filtering.** Default-deny outbound with allowlisted domains (LLM APIs, messaging services, apt, NTP). This limits exfiltration channels but doesn't prevent data leaving via allowed HTTPS endpoints -- if the agent can reach `api.anthropic.com`, it can send data there.

**Telegram pairing mode.** The `dmPolicy` defaults to `pairing`, not `open`. Unknown senders get a pairing code that the owner must approve. This prevents random strangers from querying the bot for your journal contents.

**gitleaks in the sync-gate pipeline.** When changes sync from the VM overlay back to the host, `sync-gate.sh` runs gitleaks on the staging directory. If it finds anything that looks like a secret, the sync aborts. This catches accidental secret commits before they reach the host repo.

```bash
# From scripts/sync-gate.sh
if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --source="$STAGING_DIR" --no-git --no-banner
fi
```

**.gitignore coverage.** Standard patterns for `*.key`, `.env`, `.env.*`, `secrets.yml`, `secrets.yaml`. Not bulletproof (you can always `git add -f`), but catches the common accidents.

## Gaps

!!! danger "The big one"
    There is no LLM output filtering. If the agent has a secret in its environment and a prompt injection tricks it into echoing that value, nothing stops it. This is hard to solve without breaking legitimate use cases, but it's worth being honest about.

- **No output sanitization.** The gateway does not filter LLM responses for patterns that look like API keys, PII, or other sensitive data. A well-crafted prompt injection could extract environment variables.
- **Telegram sees everything.** Even with pairing mode enabled, message content transits Telegram's servers in cleartext (Telegram's MTProto, not E2E encrypted for bots). Your journal insights are visible to Telegram.
- **Mount permissions are broad.** `/mnt/secrets` is read-only but readable by any process in the VM. `/mnt/openclaw` and `/mnt/obsidian` are writable. A compromised process in the VM can read vault contents or modify the OpenClaw repo (supply chain risk).
- **No secret rotation automation.** Keys are static until manually rotated. There's no expiry tracking or rotation reminders.
- **No audit of secret access.** We know secrets exist in `secrets.env`, but there's no `auditd` rule or equivalent tracking which processes read the file and when.

## Cross-References

- [Threat Model](../threat-model.md) -- trust boundaries and data flow
- [Secrets Configuration](../../configuration/secrets.md) -- how to provision secrets
- [Spoofing](./spoofing.md) -- identity compromise leads to disclosure
- [Denial of Service](./denial-of-service.md) -- cost exposure is a form of disclosure
- [Sync Gate Usage](../../usage/sync-gate.md) -- gitleaks integration details
- [Network Policy](../../configuration/network-policy.md) -- egress filtering rules
