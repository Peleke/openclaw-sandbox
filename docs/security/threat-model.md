# Threat Model

Yes, we know OpenClaw Sandbox is not enterprise-secure. It is a hobby project that runs AI agents inside a Lima VM. People love to point this out, as if we hadn't noticed.

The reason we do threat modeling is not to posture about our "security posture." It is because we would rather think systematically about what could go wrong *before* we start bolting on security controls at random. A dumpster fire is still a dumpster fire, but at least we can map out where the flames are hottest.

This document covers what we are protecting, where the trust boundaries are, how we use STRIDE to categorize threats, and an honest accounting of what we have actually mitigated versus what is still wide open.

---

## What We Are Protecting

Before you can secure anything, you need to know what "anything" is. Here is the asset inventory, kept deliberately short:

| Category | Assets | Why It Matters |
|----------|--------|----------------|
| **Secrets** | API keys (Anthropic, OpenAI, OpenRouter), bot tokens (Telegram), gateway credentials | Someone burns through your API credits or impersonates your bot |
| **Data** | Obsidian vault, journal entries, agent outputs, conversation history | Personal data exfiltration, context leakage to LLMs |
| **Infrastructure** | Lima VM, UFW rules, systemd services, mount points, Docker sandbox | Lateral movement, container escape, firewall bypass |
| **Availability** | LLM API access, Telegram delivery, gateway uptime | Cost amplification, service disruption |

!!! note "Scope"
    We scope this to the sandbox itself: the Lima VM, its services, and the boundary between host and VM. We do **not** cover upstream OpenClaw core, macOS host-level security (assumed trusted), physical access, or social engineering. If someone has physical access to your machine, you have bigger problems than this document can address.

---

## Trust Boundaries

The system is a set of nested trust zones. Each boundary crossing is a place where things can go wrong.

![Trust boundary diagram showing nested zones from host to external services](../diagrams/threat-model-trust-boundaries.svg)

| Boundary | Trust Level | What Lives Here |
|----------|-------------|-----------------|
| **TB1: macOS Host** | HIGH | Operator, secrets file, source repo, Obsidian vault |
| **TB2: Lima VM** | MEDIUM | Ubuntu kernel, UFW, secrets.env, systemd services |
| **TB3: Service User** | MEDIUM | Gateway process, Cadence service (non-root) |
| **TB4: Docker Sandbox** | LOW | Per-session containers where agents actually run tools |
| **TB5: External** | UNTRUSTED | LLM APIs, Telegram users, npm registry |

The key insight: data flows *down* trust levels easily (host mounts into VM, VM runs containers), but we need controls at every boundary to prevent data flowing *back up*. The sync-gate exists specifically because the overlay catches all writes in the VM, and nothing gets back to the host without gitleaks scanning and human approval.

---

## STRIDE: How We Categorize Threats

STRIDE is Microsoft's threat classification model. Six categories, each targeting a different security property:

| | Threat | Violated Property | The Question |
|---|--------|-------------------|-------------|
| **S** | Spoofing | Authentication | Can someone pretend to be a legitimate user or system? |
| **T** | Tampering | Integrity | Can data be modified without authorization? |
| **R** | Repudiation | Non-repudiation | Can someone do something and deny it afterward? |
| **I** | Information Disclosure | Confidentiality | Can secrets or private data leak? |
| **D** | Denial of Service | Availability | Can the system be exhausted or made unavailable? |
| **E** | Elevation of Privilege | Authorization | Can someone gain access they should not have? |

We apply STRIDE per component: what can go wrong with the Telegram integration? The gateway? The secrets pipeline? The supply chain? Each of those analyses lives in its own document (see [Appendix A](#appendix-a-stride-analyses) below).

### AI-Specific Extensions

Standard STRIDE was built for traditional software. AI agents add a few wrinkles:

| Threat | What It Means | Maps To |
|--------|---------------|---------|
| Prompt injection | Malicious input hijacks agent behavior | Tampering + Elevation |
| Cost amplification | Attacks that burn through API credits | DoS (financial) |
| Context leakage | Agent reveals training data or system prompts | Information Disclosure |
| Capability escalation | Agent gains access to tools it should not have | Elevation of Privilege |

These are not theoretical. If you expose an LLM-backed agent to the internet via Telegram, prompt injection is not a question of *if* but *when*.

---

## Risk Register

Here is what we have actually identified, scored honestly. Likelihood and impact are both 1-5. Risk = Likelihood x Impact. The status column is the part that matters most.

| ID | Threat | STRIDE | L | I | Risk | Status |
|----|--------|--------|---|---|------|--------|
| T-001 | Telegram open access (pre-pairing) | S/D | 5 | 4 | **20** | **Fixed** (pairing-based auth) |
| T-002 | API credit exhaustion | D | 4 | 3 | **12** | Gap -- no rate limiting |
| T-003 | Secrets in logs | I | 2 | 5 | **10** | Mitigated (env file, 0600 perms) |
| T-004 | Supply chain compromise (npm) | T/E | 3 | 5 | **15** | Gap -- no lockfile pinning |
| T-005 | Prompt injection via Telegram | T/E | 4 | 3 | **12** | Gap -- no input filtering |
| T-006 | VM escape | E | 1 | 5 | **5** | Mitigated (Lima + virtio isolation) |
| T-007 | Journal/vault content leak | I | 3 | 3 | **9** | Partial (read-only mount, but agent has read access) |
| T-008 | Missing audit trail | R | 4 | 2 | **8** | Partial (overlay-watcher exists, no centralized logging) |
| T-009 | Pairing flow bypass | S | 4 | 4 | **16** | **Fixed** (PR #33) |
| T-010 | Bot token theft | S/I | 2 | 4 | **8** | Partial (env-only, not rotated) |

!!! warning "Risk scoring is subjective"
    These numbers are our best estimates, not the output of some enterprise risk quantification framework. A score of 12 does not mean it is exactly twice as bad as a score of 6. Use them for relative prioritization, not absolute truth.

---

## What We Actually Do vs. What We Don't

Honesty section. Two columns.

### Controls That Exist

- **VM isolation**: Lima VM provides a real kernel boundary between the agent and the host. Not a container, an actual VM.
- **Read-only host mounts**: The source repo mounts into the VM as read-only via virtiofs. Writes land in the overlay upper layer, never touching the host.
- **Firewall**: UFW with explicit egress allowlist. Only HTTPS, DNS, and Tailscale traffic leave the VM.
- **Secrets management**: Secrets are in a dedicated env file with 0600 permissions, injected via systemd `EnvironmentFile=`. They do not live in the repo or in Docker images.
- **Sync gate**: Changes from the VM go through gitleaks scanning, path allowlisting, and size checks before reaching the host filesystem.
- **Telegram pairing**: Bot access requires a pairing flow with a one-time code instead of being open to anyone who finds the bot.
- **Docker sandbox**: Agent tool execution happens in per-session containers with a minimal image (bookworm-slim).
- **Overlay watcher**: inotifywait-based audit log of all writes to the overlay upper layer.

### Controls That Do Not Exist (Yet)

- **Rate limiting**: Nothing stops an attacker (or a confused agent) from making thousands of API calls. This is the most expensive gap.
- **Prompt injection defense**: No input sanitization or output filtering on the Telegram-to-agent pipeline. We rely entirely on the LLM provider's built-in guardrails.
- **Supply chain hardening**: `bun install` runs in the VM, but there is no lockfile integrity verification, no SBOM, no dependency pinning beyond what upstream OpenClaw provides.
- **Secrets rotation**: Tokens are set once and never rotated. If a token leaks, it is valid until manually revoked.
- **Centralized logging**: The overlay watcher logs to a local file. There is no aggregation, no alerting, no retention policy.
- **Container network isolation**: The Docker sandbox uses bridge networking by default. Agents can make outbound network calls from within the container.

!!! tip "Prioritization"
    If you are thinking about contributing security improvements, rate limiting (T-002) and supply chain hardening (T-004) are the highest-impact gaps. Prompt injection (T-005) is important but also partly an unsolved problem industry-wide.

---

## Appendix A: STRIDE Analyses

Each STRIDE category gets its own deep-dive document with component-level analysis, specific attack scenarios, and mitigation status:

| Document | Category | Focus |
|----------|----------|-------|
| [Spoofing](stride/spoofing.md) | Spoofing | Identity and authentication in the agent pipeline |
| [Tampering](stride/tampering.md) | Tampering | Data integrity across mounts, overlay, and LLM calls |
| [Repudiation](stride/repudiation.md) | Repudiation | Audit trails for autonomous agent actions |
| [Information Disclosure](stride/information-disclosure.md) | Information Disclosure | Secrets management and data leakage paths |
| [Denial of Service](stride/denial-of-service.md) | Denial of Service | Cost control and resource exhaustion |
| [Elevation of Privilege](stride/elevation-of-privilege.md) | Elevation of Privilege | Containment boundaries and escape paths |
| [Supply Chain](stride/supply-chain.md) | Cross-cutting | Dependency trust and integrity |

---

## References

- [Microsoft STRIDE](https://docs.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) -- the original framework
- [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling) -- broader methodology guidance
- [OWASP LLM Top 10](https://owasp.org/www-project-top-10-for-large-language-model-applications/) -- AI-specific threat taxonomy
- [Lima VM Security](https://lima-vm.io/docs/security/) -- upstream isolation guarantees
