# Repudiation

Repudiation means someone does something and then credibly denies it happened. In a system where an AI agent autonomously sends messages, writes files, and burns API credits on your behalf, the question "who did that and can we prove it?" comes up more than you'd think.

OpenClaw's audit trail situation is... nascent. We have some logging. It is not comprehensive.

## Threat Inventory

| ID | Threat | Risk | Notes |
|----|--------|------|-------|
| R-1 | User denies sending a Telegram message that triggered an expensive action | Medium | Telegram provides message IDs and user IDs, but we don't log them in a structured way |
| R-2 | Agent takes action (file write, API call) with no record of what triggered it | High | Gateway logs to journald but without action-chain linking |
| R-3 | Logs are modified or deleted after the fact | High | All logs are plain files or journald -- no tamper evidence |
| R-4 | LLM API calls can't be attributed to a user or trigger | Medium | No token/cost tracking per request or per user |
| R-5 | Cadence pipeline extracts and delivers content with no provenance trail | Low | Cadence is ambient -- file watcher fires, LLM processes, digest goes out |

## What We Actually Have

**Overlay write audit watcher.** The `overlay-watcher.service` runs `inotifywait` on the overlay upper directory and logs every create, modify, delete, and move event with timestamps to `/var/log/openclaw/overlay-watcher.log`. This is the closest thing we have to a real audit trail -- it records what files changed and when, but not *who* or *why*.

```ini
# overlay-watcher.service (simplified)
ExecStart=/usr/bin/inotifywait -m -r \
  --timefmt '%Y-%m-%dT%H:%M:%S' \
  --format '%T %w%f %e' \
  -e create -e modify -e delete -e move \
  /var/overlay/openclaw/upper
StandardOutput=append:/var/log/openclaw/overlay-watcher.log
```

**journald service logs.** Both `openclaw-gateway` and `openclaw-cadence` log to the systemd journal. You can query them with `journalctl -u openclaw-gateway`. This captures stdout/stderr -- startup, errors, basic request handling -- but it's unstructured text, not audit events.

**UFW firewall logs.** Denied outbound connections are logged at a rate of `3/min` to prevent log flooding. This tells you what the VM *tried* to reach that it shouldn't have, but nothing about legitimate traffic.

**Telegram message IDs.** Telegram's API provides immutable message IDs and verified user IDs for every incoming message. We don't currently persist these in any structured log, but the data exists in the gateway's runtime if we wanted to capture it.

## Gaps

!!! warning "The honest version"
    We have filesystem-level change tracking and basic service logs. We do not have structured audit events, action attribution, tamper-evident logging, or cost tracking. If someone disputes what happened, we're grep-ing through text files and hoping for the best.

- **No structured audit events.** Everything is either `inotifywait` output or unstructured journald text. There's no event schema, no correlation IDs, no way to link "user X sent message Y which triggered LLM call Z."
- **No tamper evidence.** Logs are append-to-file or journald. Anyone with root (or a compromised service) can edit or delete them. No hash chaining, no remote shipping.
- **No action attribution chain.** The gateway processes a request, calls an LLM, maybe invokes tools, sends a response -- none of these steps are linked in the log output. You can't reconstruct the causal chain.
- **No LLM cost tracking.** We don't record which calls were made, how many tokens were consumed, or what they cost. If the bill spikes, good luck figuring out why.
- **No Cadence provenance.** The watcher fires on a file change, Cadence extracts insights, a digest goes to Telegram. There's no record of which file triggered which insight in which digest.

## What Would Actually Help

The realistic path forward (in rough priority order):

1. **Structured gateway logging** -- JSON events for message-received, llm-call, tool-invocation, response-sent, each with a request ID that links them together
2. **Persist Telegram metadata** -- message ID, user ID, timestamp from Telegram's API (not local clock) alongside each request
3. **LLM call instrumentation** -- provider, model, token counts, and the provider's request ID for every API call
4. **Forward logs off-box** -- even just shipping journald to a remote syslog would make deletion harder

None of this exists today. The overlay watcher is genuinely useful for filesystem forensics, but application-level non-repudiation is a gap.

## Cross-References

- [Threat Model](../threat-model.md) -- overall methodology and trust boundaries
- [Information Disclosure](./information-disclosure.md) -- overlaps on log exposure
- [Spoofing](./spoofing.md) -- identity verification feeds into attribution
- [Secrets Configuration](../../configuration/secrets.md) -- secrets pipeline details
