# Defense in Depth

Bilrost uses two layers of isolation that work together. Neither layer alone is sufficient -- the point is that compromising one layer does not give an attacker (or a misbehaving agent) access to your host filesystem or credentials.

![Defense in Depth](../diagrams/defense-in-depth.svg)

## The Two Layers

```
Layer 1 (VM + Overlay):   gateway process  -> VM + read-only host mounts + OverlayFS
Layer 2 (Docker):          tool execution   -> Docker container (bridge/none network)
```

### Layer 1: VM + Overlay Isolation

The gateway process -- the thing that receives agent requests and orchestrates tool calls -- runs inside a Lima VM. This layer provides:

**Read-only host mounts.** Your project files are mounted via virtiofs with `writable: false`. The agent cannot modify the originals.

**OverlayFS containment.** An overlay merges the read-only mount with a writable upper layer at `/var/lib/openclaw/overlay/openclaw/upper`. The gateway sees a unified `/workspace` and can write freely, but all writes land in the upper layer, never touching the host.

**UFW firewall.** The VM's network is locked to an explicit allowlist: HTTPS (port 443), DNS (port 53), Tailscale, and NTP. Everything else is denied and logged. There is no blanket outbound access.

**Secrets isolation.** API keys live in `/etc/openclaw/secrets.env` with mode `0600`. The gateway loads them via systemd's `EnvironmentFile=`, which means they are not embedded in the systemd unit file and are not visible via `systemctl show` -- unlike `Environment=`, which exposes values in both places. Secrets are visible in `/proc/<pid>/environ` to root, which is expected.

**Audit watcher.** An `inotifywait`-based service (`overlay-watcher.service`) monitors the overlay upper directory and logs every create, modify, delete, and move operation to `/var/log/openclaw/overlay-watcher.log`.

### Layer 2: Docker Container Sandbox

Individual tool executions -- file reads, shell commands, browser actions -- are further sandboxed inside Docker containers:

**Per-session isolation.** Each agent session gets its own container (`sandbox_scope: "session"`). Containers are ephemeral.

**Configurable networking.** The default is `bridge` (container can reach the internet for things like `npm install` or API calls). You can set `sandbox_docker_network: "none"` for full network isolation.

**Minimal image.** The sandbox uses `openclaw-sandbox:bookworm-slim` -- a Debian slim image with just the tools needed (`git`, `jq`, `gh`, `curl`). No SSH server, no package manager cache, no unnecessary attack surface.

**Workspace bind mount.** The container gets `/workspace` bind-mounted read-write, which is the overlay merged view (not the host mount). Writes from inside the container go to the overlay upper layer.

**Overlay-protected vault access.** If an Obsidian vault is mounted, it is bind-mounted into containers as read-write (`/workspace-obsidian:/workspace-obsidian:rw`). Writes land in the overlay upper layer, not on the host vault directly. The sync gate controls when changes propagate back.

## The Gated Exit Path

Writes are contained, but eventually you want changes to reach your host. That is where the sync gate comes in:

1. Agent makes changes in `/workspace` (writes land in overlay upper)
2. You run `scripts/sync-gate.sh` on the host
3. The sync gate runs a validation pipeline:
    - **gitleaks**: scans for accidentally committed secrets
    - **Path allowlist**: only approved file paths can sync
    - **Size/filetype check**: blocks unexpected large files or binary blobs
4. If validation passes, `rsync` copies approved changes from the overlay upper to the host

!!! tip
    Use `sync-gate.sh --dry-run` to see what would sync without applying anything.

In YOLO mode (`--yolo`), a systemd timer (`yolo-sync.timer`) runs `rsync` every 30 seconds, bypassing the validation pipeline. This is a convenience mode for trusted environments, not a security recommendation.

## Why Two Layers

A single layer has obvious failure modes:

**If you only had the VM (Layer 1):** The gateway process can read/write everything in the VM. A compromised gateway could exfiltrate secrets from `/etc/openclaw/secrets.env`, tamper with the overlay upper directory, or abuse Docker access. But it cannot touch the host filesystem (mounts are read-only) and it cannot reach arbitrary network destinations (firewall).

**If you only had Docker (Layer 2):** The container has a limited view of the filesystem and network. But the gateway that creates those containers runs outside them. A vulnerability in the gateway itself would bypass container isolation entirely.

**With both layers:** The gateway is isolated from the host by the VM boundary. Tool executions are isolated from the gateway by the container boundary. An attacker needs to escape the container AND the VM to reach your host -- two independent boundaries with different attack surfaces.

This is not theoretical enterprise security theater. It is a practical consequence of the fact that AI agents make unpredictable tool calls, and the gateway that dispatches those calls is itself a potential attack surface.

## Security Properties at Each Layer

| Property | Layer 1 (VM) | Layer 2 (Docker) |
|----------|-------------|-----------------|
| Filesystem | Read-only host mounts + OverlayFS | Bind mount of overlay merged view |
| Network | UFW allowlist | bridge (default) or none |
| Secrets | `0600` file, `EnvironmentFile=` | Selective env passthrough (`GH_TOKEN`) |
| Audit | inotifywait watcher on upper dir | Container logs |
| Escape to host | Requires VM escape | Requires container escape + VM escape |
| Process isolation | Separate kernel (VM) | Shared kernel, namespaced |

## What This Does Not Protect Against

Being honest about limitations:

- **A compromised LLM API** could instruct the agent to exfiltrate data through allowed HTTPS endpoints. The firewall allows port 443 outbound because the agent needs to call LLM APIs.
- **Overlay upper writes** are visible to the gateway process. If the gateway is compromised, it can read anything the agent wrote.
- **Docker is not a security boundary** in the same way a VM is. Container escapes exist. The VM layer is the hard boundary; Docker is defense in depth, not a guarantee.
- **YOLO mode** bypasses sync-gate validation. If you use `--yolo`, you are trading security for convenience.
