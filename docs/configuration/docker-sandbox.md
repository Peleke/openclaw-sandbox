# Docker Sandbox

OpenClaw's built-in sandbox containerizes individual tool executions (file reads/writes, shell commands, browser actions) inside Docker containers within the VM. This is the second layer of defense-in-depth -- the first layer is the OverlayFS isolation at the VM level.

![Defense in Depth](../diagrams/defense-in-depth.svg)

## How It Works

```
Agent request --> Gateway process (VM) --> Tool routing
                                              |
                  +---------------------------+---------------------------+
                  |                                                       |
          Isolated Container                                    Network Container
          (network: none)                                       (network: bridge)
                  |                                                       |
                  +-- /workspace bind mount (rw)                          +-- /workspace bind mount (rw)
                  +-- /workspace-obsidian bind mount (rw)                 +-- /workspace-obsidian bind mount (rw)
                  +-- air-gapped (no internet)                            +-- GH_TOKEN env var
                                                                          +-- BRAVE_API_KEY env var
                                                                          +-- bridge network (internet access)
```

The gateway spawns Docker containers for tool execution. By default, the sandbox uses **dual-container network isolation**: an air-gapped container for most operations and a bridge-networked container for tools that need internet access. The `networkAllow` and `networkExecAllow` config controls which tools and commands are routed to the network container.

## Default Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| **Mode** | `all` | Every session is sandboxed |
| **Scope** | `session` | One container per session (not per tool call) |
| **Workspace access** | `rw` | Tools can read and write project files |
| **Primary network** | `none` | Isolated container is air-gapped by default |
| **Network container** | `bridge` | Network-routed tools get internet access |
| **Image** | `openclaw-sandbox:bookworm-slim` | Debian-based with `gh` CLI |
| **networkAllow** | `[web_fetch, web_search]` | Tools routed to network container |
| **networkExecAllow** | `[gh]` | Command prefixes routed to network container |

These defaults are set in `ansible/roles/sandbox/defaults/main.yml` and injected into `~/.openclaw/openclaw.json` during provisioning.

## Per-Tool Network Isolation (Dual-Container)

The default sandbox configuration uses **dual-container network isolation**. Instead of giving every tool execution internet access (or denying it to all of them), the gateway routes each tool to one of two containers based on what it needs:

| Container | Network Mode | Purpose |
|-----------|-------------|---------|
| **Isolated** | `none` | Most tool executions (file reads/writes, shell commands) — air-gapped |
| **Network** | `bridge` | Tools that need internet (`web_fetch`, `web_search`, `gh`) |

### How Routing Works

The gateway checks two config lists to decide where a tool runs:

1. **`networkAllow`** — tool names routed to the network container. Default: `["web_fetch", "web_search"]`
2. **`networkExecAllow`** — command prefixes for shell execution routed to the network container. Default: `["gh"]`

If a tool matches either list, it runs in the bridge-networked container. Everything else runs in the isolated (air-gapped) container.

### Example: What Happens When the Agent Runs `gh pr create`

1. Agent calls the `execute` tool with command `gh pr create --title "Fix bug"`
2. Gateway sees the command prefix `gh` matches `networkExecAllow`
3. Execution is routed to the **network container** (bridge mode, has `GH_TOKEN`)
4. GitHub API call succeeds because the container has internet access

### Example: What Happens When the Agent Reads a File

1. Agent calls the `read` tool for `src/main.py`
2. Gateway checks `networkAllow` — `read` is not listed
3. Execution is routed to the **isolated container** (no network)
4. File is read from `/workspace` bind mount — no internet needed

### Configuration in openclaw.json

The dual-container config is injected into `~/.openclaw/openclaw.json` during provisioning:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "rw",
        "docker": {
          "network": "none",
          "env": {
            "GH_TOKEN": "${GH_TOKEN}",
            "BRAVE_API_KEY": "${BRAVE_API_KEY}"
          }
        },
        "networkAllow": ["web_fetch", "web_search"],
        "networkExecAllow": ["gh"],
        "networkDocker": {
          "network": "bridge"
        }
      }
    }
  }
}
```

Key fields:

- `docker.network: "none"` — the **primary (isolated) container** has no network
- `networkAllow` — tool names routed to the network container
- `networkExecAllow` — command prefixes routed to the network container
- `networkDocker.network: "bridge"` — the **network container** has bridge networking

### Operator Extension Variables

Operators can add extra tools or command prefixes to the network-routed lists without overriding the defaults:

```bash
bilrost up  # after setting extra_vars in your profile, or:
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e '{"sandbox_network_allow_extra": ["mcp_fetch"]}' \
  -e '{"sandbox_network_exec_allow_extra": ["curl", "npm"]}'
```

| Variable | Default | Description |
|----------|---------|-------------|
| `sandbox_network_allow_extra` | `[]` | Additional tool names for network routing |
| `sandbox_network_exec_allow_extra` | `[]` | Additional command prefixes for network routing |

These are merged with the base lists at provisioning time.

### Disabling Dual-Container Mode

To give all tools network access (single bridge container):

```bash
bilrost up  # with extra_vars: sandbox_docker_network=bridge
# or
./bootstrap.sh --openclaw ~/Projects/openclaw -e "sandbox_docker_network=bridge"
```

To deny all tools network access (single air-gapped container, clear the routing lists):

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e '{"sandbox_network_allow": [], "sandbox_network_exec_allow": []}'
```

## Legacy Network Modes

For simpler configurations without per-tool routing, you can set a single network mode for all tools.

### Bridge

```bash
bilrost up  # with extra_vars: sandbox_docker_network=bridge
# or
./bootstrap.sh --openclaw ~/Projects/openclaw -e "sandbox_docker_network=bridge"
```

Standard Docker networking. Containers get their own network namespace with NAT to the host. They can reach the internet (subject to the VM's UFW rules) for tasks like `npm install`, `curl`, or `gh api` calls.

### None (maximum isolation)

```bash
bilrost up  # with extra_vars: sandbox_docker_network=none
# or
./bootstrap.sh --openclaw ~/Projects/openclaw -e "sandbox_docker_network=none"
```

No network at all. Containers cannot make any network requests. Use this when you want tool executions to be completely offline -- the agent can still make LLM API calls from the gateway process, but tool executions in the container are air-gapped.

!!! tip "Choosing a network mode"
    The default dual-container setup is recommended: most tools run air-gapped while `web_fetch`, `web_search`, and `gh` get internet access. Override to single-mode `bridge` only if your agent needs broad internet access (e.g., `npm install`, `curl`).

## Image: `openclaw-sandbox:bookworm-slim`

The sandbox image is built in one of three ways:

### 1. Project build script (primary)

If `scripts/sandbox-setup.sh` exists in your OpenClaw repo, the sandbox role runs it to build the image:

```bash
cd /workspace && bash scripts/sandbox-setup.sh
```

### 2. Fallback image (no build script)

If the build script does not exist, the sandbox role builds a minimal Debian image with `gh` pre-installed:

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq gnupg && \
    # ... GitHub CLI APT repo setup ... \
    apt-get install -y --no-install-recommends gh
RUN useradd -m -s /bin/bash sandbox
USER sandbox
WORKDIR /workspace
```

### 3. Image augmentation (gh CLI layering)

After the image is built (by either method), the sandbox role checks if `gh` is available inside the image. If not, it layers `gh` on top:

```bash
# The role runs this check:
docker run --rm openclaw-sandbox:bookworm-slim which gh
```

If `which gh` fails, the role builds a new layer:

```dockerfile
FROM openclaw-sandbox:bookworm-slim
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg && \
    # ... GitHub CLI APT repo setup ... \
    apt-get install -y --no-install-recommends gh
# Restore original USER
USER <original-user>
```

!!! note "Idempotent augmentation"
    The `which gh` check makes augmentation idempotent. If the base image already has `gh`, no extra layer is added. If you rebuild the base image without `gh`, the augmentation layer will be reapplied on next provision.

## Sandbox Docker Environment Passthrough

The sandbox role configures environment variable passthrough in `openclaw.json`. Variables are passed to the network container (which has bridge networking) so they can be used by tools that need API access:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "env": {
            "GH_TOKEN": "${GH_TOKEN}",
            "BRAVE_API_KEY": "${BRAVE_API_KEY}"
          }
        }
      }
    }
  }
}
```

The `${GH_TOKEN}` syntax means "take the value of `GH_TOKEN` from the gateway's environment and pass it into the container." Since the gateway loads secrets via `EnvironmentFile=/etc/openclaw/secrets.env`, the token flows through without being hardcoded anywhere.

Currently two variables are passed through:

- **`GH_TOKEN`** — for GitHub CLI operations (`gh pr create`, `gh api`, etc.)
- **`BRAVE_API_KEY`** — for `web_search` tool via the Brave Search API

## Vault Bind Mount

When an Obsidian vault is mounted via `--vault`, the overlay at `/workspace-obsidian` is bind-mounted into sandbox containers as **read-write** by default:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "binds": ["/workspace-obsidian:/workspace-obsidian:rw"]
        }
      }
    }
  }
}
```

Writes inside the container land in the OverlayFS upper layer, not directly on the host vault. The sync gate controls when changes propagate back. To lock the vault to read-only, override with `-e "sandbox_vault_access=ro"`.

The bind mount is only added if `/workspace-obsidian` exists on the VM. If you re-provision without `--vault`, the bind mount entry remains in `openclaw.json` but Docker will fail gracefully if the source path doesn't exist.

## Disabling Docker Sandbox

To run a lighter VM without Docker:

```bash
# Using the Python CLI (recommended)
bilrost up  # after running: bilrost init (and selecting --no-docker in profile)

# Using bootstrap.sh directly
./bootstrap.sh --openclaw ~/Projects/openclaw --no-docker
```

This sets `docker_enabled=false`, which skips both the Docker CE installation and the sandbox role entirely. The gateway still runs, but tool executions happen directly in the VM (protected by OverlayFS isolation).

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `sandbox_enabled` | `{{ docker_enabled }}` | Follows the Docker master switch |
| `sandbox_mode` | `all` | `off`, `non-main`, `all` |
| `sandbox_scope` | `session` | `session`, `agent`, `shared` |
| `sandbox_workspace_access` | `rw` | `none`, `ro`, `rw` |
| `sandbox_image` | `openclaw-sandbox:bookworm-slim` | Docker image name |
| `sandbox_build_browser` | `false` | Also build the browser sandbox image |
| `sandbox_docker_network` | `none` | Primary container: `bridge`, `host`, `none` |
| `sandbox_network_allow` | `[web_fetch, web_search]` | Tools routed to network container |
| `sandbox_network_allow_extra` | `[]` | Operator-provided extra tools for network routing |
| `sandbox_network_exec_allow` | `[gh]` | Command prefixes routed to network container |
| `sandbox_network_exec_allow_extra` | `[]` | Operator-provided extra command prefixes |
| `sandbox_network_docker_network` | `bridge` | Network container mode: `bridge`, `host` |
| `sandbox_setup_script` | `scripts/sandbox-setup.sh` | Build script relative to workspace |
| `sandbox_vault_path` | `/workspace-obsidian` | Vault bind mount source |
| `sandbox_vault_access` | `rw` | Vault access in container: `ro`, `rw` |

Override any of these with `-e`:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw \
  -e "sandbox_docker_network=none" \
  -e "sandbox_workspace_access=ro"
```

## Verification Commands

```bash
# Check Docker is running in VM
limactl shell openclaw-sandbox -- docker info

# Check sandbox image exists
limactl shell openclaw-sandbox -- docker images | grep openclaw-sandbox

# Verify gh is in the sandbox image
limactl shell openclaw-sandbox -- docker run --rm openclaw-sandbox:bookworm-slim gh --version

# See active sandbox containers
limactl shell openclaw-sandbox -- docker ps -a

# Check sandbox config in openclaw.json
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox' ~/.openclaw/openclaw.json

# Check Docker network mode
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.network' ~/.openclaw/openclaw.json

# Check vault bind mount
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.binds' ~/.openclaw/openclaw.json

# Check env passthrough
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.env' ~/.openclaw/openclaw.json

# Test vault is visible inside a container
limactl shell openclaw-sandbox -- docker run --rm \
  -v /workspace-obsidian:/workspace-obsidian:ro alpine ls /workspace-obsidian
```
