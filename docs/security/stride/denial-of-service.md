# Denial of Service

Traditional DoS exhausts compute. AI-system DoS exhausts your wallet. When every inbound message can trigger multiple LLM API calls at $0.01-$10 each, the economics of denial of service change dramatically. One Telegram message to an unprotected OpenClaw gateway can cascade into multi-dollar API costs -- and there's nothing stopping someone from sending thousands of them.

This is the threat category where OpenClaw has the most surface area and the fewest controls.

## Threat Inventory

| ID | Threat | Risk | Notes |
|----|--------|------|-------|
| D-1 | Telegram message flooding burns API credits | High | Pairing mode limits *who* can send, but not *how much* a paired user can send |
| D-2 | Crafted prompts maximize token consumption | High | Long inputs, multi-turn reasoning, tool loops -- all legal requests that cost disproportionately |
| D-3 | Pairing request spam blocks legitimate users | Medium | Pairing store caps at 50 pending requests; flooding it returns empty codes |
| D-4 | Rapid file changes in mounted vault overwhelm Cadence | Medium | Each file change triggers watcher, which can trigger LLM extraction |
| D-5 | Disk exhaustion via workspace writes or log flooding | Medium | No workspace quotas, no journal size limits |
| D-6 | Memory exhaustion from concurrent long-context requests | Medium | No concurrency limits on the gateway process |

!!! note "The cost amplification math"
    A single Telegram message can trigger multiple LLM API calls (context loading, reasoning, tool use, response generation). At 60 messages/hour with $0.50 average cost per exchange, that's $1,800/day from one attacker. With expensive models or tool loops, it can be much worse.

## What We Actually Have

**UFW default-deny egress.** The firewall blocks all outbound traffic except allowlisted domains (LLM APIs, messaging services, DNS, NTP, apt). This is network containment, not DoS protection -- it limits where data can go but doesn't limit how much goes there.

**Telegram pairing mode.** With `dmPolicy: pairing`, only approved users can interact with the bot. This is the single most effective DoS control we have -- it turns an open attack surface into one that requires authorization. But it doesn't rate-limit approved users.

```yaml
# ansible/roles/gateway/tasks/fix-vm-paths.yml
- name: Set Telegram dmPolicy to pairing (secure default)
    ...
    'dmPolicy': 'pairing'
```

**Firewall log rate limiting.** UFW logging is capped at `3/min` (`firewall_log_limit`) to prevent log-based disk exhaustion. This is a narrow control for a narrow problem.

That's it. That's the list.

## Gaps

!!! danger "No application-layer rate limiting"
    There is no rate limiting, cost budgeting, concurrency control, input size validation, tool iteration capping, or workspace quotas. The firewall handles network-layer containment. Everything above that is wide open.

- **No per-user rate limiting.** A paired user can send unlimited messages at any rate. There's no sliding window, no cooldown, no daily cap.
- **No cost budgets.** There's no tracking of API spend per user, per day, or globally. No circuit breaker when costs spike. If your API key has a high limit, so does your exposure.
- **No input size validation.** Messages of any length are passed directly to the LLM. Maximum context window prompts repeated rapidly can exhaust both memory and API budget.
- **No tool iteration limits.** If a prompt causes the agent to enter a tool-use loop (search, then search the results, then search those results...), there's no cap on iterations. Each iteration costs tokens.
- **No concurrency limits.** The gateway doesn't cap concurrent requests. Multiple simultaneous long-running requests can exhaust memory and block the Node.js event loop.
- **No workspace quotas.** Agent file writes go to the overlay workspace with no size limits. Fill the disk, break the VM.
- **No monitoring or alerting.** There's no visibility into request rates, cost accumulation, or queue depth. You find out about a DoS attack when you check your API provider's billing page.

## What Would Actually Help

The realistic mitigations, ordered by bang-for-buck:

1. **Keep pairing mode on.** Seriously. This is the single biggest DoS control. An unauthenticated attacker can't burn your API credits if they can't talk to the bot.
2. **Set provider-side spending limits.** Anthropic and OpenAI both support monthly spend caps in their dashboards. This is the cheapest circuit breaker available -- use it.
3. **systemd resource limits.** Add `MemoryMax=`, `LimitNPROC=`, and `LimitNOFILE=` to the gateway service unit. Doesn't prevent DoS but prevents it from taking down the whole VM.
4. **Per-user rate limiting in the gateway.** This requires upstream changes to OpenClaw's gateway, but a simple sliding-window limiter (10 messages/minute/user) would cap the blast radius of a compromised or abusive paired user.
5. **Tool iteration caps.** Bound the number of tool calls per request. This is an upstream change but prevents the worst cost amplification scenarios.

!!! tip "The provider-side spending cap"
    Until the gateway has real rate limiting, set a monthly spending cap on your LLM provider accounts. This is your last line of defense and it costs nothing to configure.

## Cross-References

- [Threat Model](../threat-model.md) -- overall risk model and trust boundaries
- [Repudiation](./repudiation.md) -- cost attribution requires audit trails
- [Information Disclosure](./information-disclosure.md) -- related via API key exposure
- [Network Policy](../../configuration/network-policy.md) -- UFW egress rules
- [Telegram Configuration](../../configuration/telegram.md) -- pairing mode setup
