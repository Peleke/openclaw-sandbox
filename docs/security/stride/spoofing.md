# Spoofing

Spoofing means someone pretends to be a legitimate identity. In an AI agent sandbox, this is worse than usual: a spoofed identity doesn't just get access to data, it gets to _tell an autonomous agent what to do_. The agent doesn't know the difference between a real user and a convincing fake.

OpenClaw has four identity domains, each with its own spoofing surface:

- **Human identity** -- Telegram users sending commands to the agent
- **Service identity** -- the bot token proving the gateway is who it says it is
- **Machine identity** -- the Lima VM as a trusted execution environment
- **API identity** -- LLM provider credentials (Anthropic, OpenAI, etc.)

## Threat Inventory

| Threat | Vector | Difficulty | Impact | Notes |
|--------|--------|------------|--------|-------|
| Telegram user impersonation | Steal session or social-engineer admin into approving attacker | Medium | Critical | Telegram cryptographically signs user IDs, so direct forgery requires compromising Telegram itself |
| Pairing flow bypass | Exhaust pending pairing limit to produce empty codes, then social-engineer admin | Medium | Critical | See [pairing bugs](#pairing-flow-bugs) below |
| Bot token theft | Token in logs, process env, git history, or host secrets file | Low-Medium | Critical | Token gives full bot impersonation -- webhook hijack, message forgery, the works |
| API key theft and reuse | Read secrets file, prompt injection exfiltration, host compromise | Medium | Critical | Stolen API keys mean credit theft and potential data access on provider side |
| VM image tampering | MITM during Lima image download; no checksum verification | Medium | Critical | Malicious VM image = game over, all secrets compromised at boot |
| SSH key injection | Add attacker key during provisioning | Medium | High | Lima manages SSH keys; attack requires intercepting provisioning |

## Pairing Flow Bugs

The Telegram pairing system has several known issues that compound into a real spoofing risk. None of these are individually catastrophic, but chained together they allow an attacker to replace a legitimate user:

1. **Empty code at limit** -- when 50 pairing requests are pending, new requests get an empty code instead of an error. The user sees "Pairing code: " with nothing after it.
2. **Silent send failure** -- if the pairing DM fails to send, the error is swallowed (`.catch(() => {})`). The pairing state is now inconsistent.
3. **No pre-flight check** -- nobody verifies the bot _can_ send DMs before enabling pairing mode. If it can't, all pairing silently fails.
4. **Normalization mismatch** -- `allowFrom` stores `telegram:123` but the auth check normalizes to `123`. Legitimate user gets denied.
5. **Approval notification swallowed** -- admin approves a user, notification fails silently. User doesn't know they were approved, gives up.

The chain attack: flood pairing to trigger bug 1, legitimate user gets frustrated, attacker social-engineers admin ("I'm that user, pairing didn't work"), admin adds attacker, legitimate user still blocked by bug 4.

!!! warning "These are upstream OpenClaw bugs"
    The sandbox can't fix these directly. The workaround is using explicit `allowFrom` lists instead of relying on the pairing flow.

## What We Do About It

| Control | What it does | Status |
|---------|-------------|--------|
| Secrets file permissions (0600) | Prevents casual reads of `/etc/openclaw/secrets.env` | Done |
| `EnvironmentFile=` in systemd | Keeps tokens out of `ps` output (vs. `Environment=`) | Done |
| `no_log: true` in Ansible | Prevents secret values appearing in provision logs | Done |
| Read-only secrets mount | Host secrets file mounted read-only into VM | Done |
| UFW default-deny | Limits network paths for exfiltrating stolen credentials | Done |
| Pairing mode available | `dmPolicy: "pairing"` restricts who can talk to the bot | Available (buggy) |
| Explicit allowlist | `allowFrom` configuration for known user IDs | Done |
| VZ hypervisor isolation | Lima VM runs in Apple's Virtualization.framework | Done |

## Gaps

These are real gaps. We know about them. Some have workarounds, some don't.

| Gap | Risk | Workaround |
|-----|------|------------|
| No image checksum verification | VM image could be tampered in transit | Lima fetches from canonical Ubuntu URLs over HTTPS, which helps but isn't a checksum |
| Pairing flow bugs (5 identified) | Pairing is unreliable; use explicit allowlists instead | Use `allowFrom` with known user IDs, don't rely on pairing |
| No webhook secret validation | Forged webhook requests could inject messages | Gateway uses polling mode by default, which sidesteps this |
| No rate limiting on auth | Brute force on gateway password is possible | UFW limits network surface; gateway is VM-internal only |
| No auth event audit logging | Can't forensically investigate spoofing attempts | Systemd journal captures gateway logs, but no structured auth events |
| No API key rotation tooling | Compromised keys stay valid until manually rotated | Manual rotation via provider dashboards |

## Cross-References

- [Threat Model](../threat-model.md) -- overall methodology and risk register
- [Tampering](./tampering.md) -- prompt injection is the tampering analog to spoofing
- [Information Disclosure](./information-disclosure.md) -- secret leakage enables spoofing
- [Secrets Pipeline](../../architecture/secrets-pipeline.md) -- how secrets flow through the system
- [Telegram Configuration](../../configuration/telegram.md) -- pairing and allowlist setup
