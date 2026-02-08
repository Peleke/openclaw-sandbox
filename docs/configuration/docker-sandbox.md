# Docker Sandbox

OpenClaw's built-in sandbox containerizes individual tool executions (file reads/writes, shell commands, browser actions) inside Docker containers within the VM. This is the second layer of defense-in-depth -- the first layer is the OverlayFS isolation at the VM level.

![Defense in Depth](../diagrams/defense-in-depth.svg)

## How It Works

```
Agent request --> Gateway process (VM) --> Tool execution --> Docker container
                                                              |
                                                              +-- /workspace bind mount (rw)
                                                              +-- /workspace-obsidian bind mount (ro)
                                                              +-- GH_TOKEN env var (if configured)
                                                              +-- bridge network (internet access)
```

The gateway spawns a Docker container for each tool execution. The container gets bind mounts to the workspace and (optionally) the Obsidian vault, plus any environment variables configured for passthrough.

## Default Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| **Mode** | `all` | Every session is sandboxed |
| **Scope** | `session` | One container per session (not per tool call) |
| **Workspace access** | `rw` | Tools can read and write project files |
| **Network** | `bridge` | Containers can reach the internet |
| **Image** | `openclaw-sandbox:bookworm-slim` | Debian-based with `gh` CLI |

These defaults are set in `ansible/roles/sandbox/defaults/main.yml` and injected into `~/.openclaw/openclaw.json` during provisioning.

## Network Modes

### Bridge (default)

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
# sandbox_docker_network defaults to "bridge"
```

Standard Docker networking. Containers get their own network namespace with NAT to the host. They can reach the internet (subject to the VM's UFW rules) for tasks like `npm install`, `curl`, or `gh api` calls.

### None (maximum isolation)

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw -e "sandbox_docker_network=none"
```

No network at all. Containers cannot make any network requests. Use this when you want tool executions to be completely offline -- the agent can still make LLM API calls from the gateway process, but tool executions in the container are air-gapped.

!!! tip "Choosing a network mode"
    Use `bridge` if your agent needs to run `npm install`, `gh pr create`, `curl`, or any command that requires internet access. Use `none` if you want maximum isolation and your agent only needs file operations and shell commands.

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

The sandbox role configures environment variable passthrough in `openclaw.json`. Currently, `GH_TOKEN` is the only variable passed through:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "rw",
        "docker": {
          "network": "bridge",
          "env": {
            "GH_TOKEN": "${GH_TOKEN}"
          }
        }
      }
    }
  }
}
```

The `${GH_TOKEN}` syntax means "take the value of `GH_TOKEN` from the gateway's environment and pass it into the container." Since the gateway loads secrets via `EnvironmentFile=/etc/openclaw/secrets.env`, the token flows through without being hardcoded anywhere.

## Vault Bind Mount

When an Obsidian vault is mounted via `--vault`, the overlay at `/workspace-obsidian` is bind-mounted into sandbox containers as **read-only**:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "binds": ["/workspace-obsidian:/workspace-obsidian:ro"]
        }
      }
    }
  }
}
```

This gives agents inside sandbox containers access to vault files for context, without being able to modify them.

The bind mount is only added if `/workspace-obsidian` exists on the VM. If you re-provision without `--vault`, the bind mount entry remains in `openclaw.json` but Docker will fail gracefully if the source path doesn't exist.

## Disabling Docker Sandbox

To run a lighter VM without Docker:

```bash
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
| `sandbox_docker_network` | `bridge` | `bridge`, `host`, `none` |
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
