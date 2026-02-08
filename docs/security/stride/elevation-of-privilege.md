# Elevation of Privilege

We run arbitrary LLM-generated code inside a VM that has API keys, Docker access, and writable mounts back to the host. The question isn't whether there are privilege escalation paths -- it's how many layers an attacker has to punch through.

This analysis enumerates the realistic escalation vectors for the Bilrost and is honest about which ones we've addressed and which ones remain open.

## Privilege Boundaries

The sandbox has four privilege layers, from most to least trusted:

| Layer | What lives here | Escape impact |
|-------|----------------|---------------|
| **macOS host** | User session, Lima manager, Homebrew, host filesystem | Game over -- full access to everything |
| **VM root** | systemd, UFW, Docker daemon, `/etc/openclaw/secrets.env` | Can read all secrets, modify firewall, control all services |
| **VM user** | Gateway process, Bun, Node.js, overlay workspace | Can execute code, read own env vars, write to overlay upper |
| **Docker sandbox** | Per-session containers for tool execution | Contained -- no secrets, no host mounts (in theory) |

The interesting attacks cross these boundaries.

## Attack Surface

| Vector | From | To | Likelihood | Impact | Notes |
|--------|------|----|-----------|--------|-------|
| VM escape via VZ framework | VM | macOS host | Very low | Critical | Apple Virtualization Framework; hardware-assisted isolation. Requires a hypervisor 0-day. |
| VM escape via virtio-fs | VM | macOS host | Low | Critical | Lima's filesystem sharing layer. Bugs here could leak host memory or allow writes outside mounts. |
| Sudo to root in VM | VM user | VM root | Medium | High | Lima's default user has passwordless sudo. No sudoers hardening applied. |
| Docker socket access | VM user | VM root-equivalent | Medium | High | Gateway has `SupplementaryGroups=docker`. Docker socket = root-equivalent access. |
| Container breakout | Docker sandbox | VM user/root | Low | High | Standard container escape vectors (kernel exploits, capabilities, mounted sockets). |
| Overlay escape via symlinks | VM user | Host files (read) | Low | Medium | Symlink in overlay upper pointing outside mount. VZ enforces mount boundaries, but worth noting. |
| Agent config tampering | Agent | Expanded capabilities | Medium | High | Agent writes to workspace, which may include config files that the gateway reads. |
| Secrets file read | VM user | API keys | Already possible | High | Gateway process can read its own env. Any code running as that user gets the keys. |

## What We Actually Do

**VM isolation (strong)**. Lima uses Apple's Virtualization Framework with hardware-assisted memory isolation. Separate kernel, separate userspace. This is the big one -- it means a compromised VM doesn't automatically mean a compromised host.

**Non-root services**. Gateway and Cadence run as the Lima user via `User=` in their systemd units. Not root.

**OverlayFS**. Host mounts are read-only lowerdirs. Writes land in the overlay upper directory inside the VM. The host filesystem doesn't see agent writes unless explicitly synced through sync-gate.

**Docker sandbox**. Tool execution happens in per-session containers built from a base image. The sandbox configuration is injected into `openclaw.json` via the sandbox role.

**UFW default-deny**. Outbound traffic is blocked by default with an explicit allowlist: DNS (53), HTTP (80 for apt), HTTPS (443 for LLM APIs), and Tailscale CIDR. No arbitrary outbound connections.

**Secrets isolation**. `/etc/openclaw/secrets.env` is mode 0600, loaded via `EnvironmentFile=` (not `Environment=`, so not in `ps` output), and all Ansible handling uses `no_log: true`.

## Gaps

!!! warning "Docker socket = root"
    The gateway has `SupplementaryGroups=docker` so it can manage sandbox containers. But Docker socket access is effectively root-equivalent inside the VM. Any code running as the gateway user can `docker run --privileged` or mount the host filesystem. This is a known trade-off: the gateway needs Docker access to do its job.

!!! warning "Passwordless sudo"
    Lima's default user has passwordless sudo. We haven't hardened `/etc/sudoers`. This means any code execution as the VM user trivially escalates to VM root.

**No systemd hardening**. The gateway service unit doesn't use `NoNewPrivileges=`, `ProtectSystem=`, `CapabilityBoundingSet=`, or `SystemCallFilter=`. These are straightforward to add and would limit blast radius if the gateway process is compromised.

**No seccomp or AppArmor**. Neither the gateway process nor sandbox containers have mandatory access control profiles. Docker's default seccomp profile applies to sandbox containers, but nothing custom.

**Agent can influence its own config**. If the agent's workspace contains config files that the gateway reads on restart, the agent can modify its own capabilities. This is inherent to the architecture -- the workspace is writable by design.

## What's Realistic

For a hobby project running on a personal Mac, the layering is actually decent:

- **VM isolation** handles the catastrophic case (agent compromises VM, host stays safe)
- **OverlayFS** prevents agent writes from contaminating the host source tree
- **UFW** limits exfiltration to HTTPS (which is still a wide channel, but better than unrestricted)
- **Docker sandbox** adds a layer between tool execution and the VM user

The gaps that would be worth closing, roughly in priority order:

1. **Systemd unit hardening** -- `NoNewPrivileges=yes`, `ProtectSystem=strict`, `CapabilityBoundingSet=` are low-effort, high-value additions
2. **Sudoers restriction** -- limit passwordless sudo to specific commands the provisioning actually needs
3. **Docker socket scoping** -- consider using Docker's `--userns-remap` or rootless Docker to reduce the blast radius of socket access

Things that are probably not worth doing for a hobby project: custom seccomp profiles, SELinux/AppArmor policy writing, VM escape detection via auditd. The VZ framework is Apple's hypervisor -- if that has a 0-day, you have bigger problems than this sandbox.

## Cross-References

- [Threat Model](../threat-model.md) -- overall methodology and trust boundaries
- [Tampering](./tampering.md) -- config and filesystem integrity
- [Information Disclosure](./information-disclosure.md) -- secrets exposure paths
- [Supply Chain](./supply-chain.md) -- pre-sandbox code execution during provisioning
