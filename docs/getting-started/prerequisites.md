# Prerequisites

Before you install OpenClaw Sandbox, make sure your machine meets a few basic requirements. The bootstrap script handles most of the heavy lifting, but it needs a couple of things to already be in place.

## System Requirements

### macOS

OpenClaw Sandbox runs on **macOS only** -- it uses [Lima](https://lima-vm.io/) to manage a Linux VM via Apple's Virtualization framework. Both Apple Silicon (M1/M2/M3/M4) and Intel Macs are supported.

!!! note
    On Apple Silicon, the VM uses Rosetta for x86_64 emulation automatically. You do not need to configure this yourself.

### Disk Space

Plan for roughly **10 GB** of free disk space. This covers the Ubuntu 24.04 VM image, Docker images inside the VM, and the OverlayFS layers that store your workspace writes.

### Memory and CPU

The VM defaults to **4 CPUs** and **8 GiB of RAM**. You can override these at bootstrap time with environment variables:

```bash
VM_CPUS=2 VM_MEMORY=4GiB ./bootstrap.sh --openclaw ~/Projects/openclaw
```

The disk defaults to **50 GiB** (thin-provisioned, so it only uses what it needs).

## Required: Homebrew

[Homebrew](https://brew.sh/) is the only thing you need to install manually. Everything else is pulled in by the bootstrap script.

If you do not have Homebrew yet:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

!!! warning
    The bootstrap script will exit with an error if Homebrew is not found. It will not attempt to install it for you.

## Auto-Installed Dependencies

When you run `bootstrap.sh`, it installs the following from the project's `brew/Brewfile`:

| Dependency | Type | Purpose |
|---|---|---|
| [Lima](https://lima-vm.io/) | `brew` | Linux VM manager for macOS. Creates and manages the sandbox VM. |
| [Ansible](https://www.ansible.com/) | `brew` | Configuration management. Provisions everything inside the VM. |
| [jq](https://jqlang.github.io/jq/) | `brew` | JSON processor. Used by `bootstrap.sh` to parse Lima output. |
| [gitleaks](https://github.com/gitleaks/gitleaks) | `brew` | Secret scanning. Powers the sync-gate validation pipeline. |
| [Tailscale](https://tailscale.com/) | `cask` | Secure private networking. Optional -- used if you need the VM to reach devices on your Tailnet. |

You do not need to install any of these beforehand. The bootstrap handles it via `brew bundle`.

!!! tip
    If you already have some of these installed, `brew bundle` will skip them. It is safe to re-run.

## Optional: An OpenClaw Clone

You will need a local clone of the [OpenClaw](https://github.com/Peleke/openclaw) repository. The bootstrap script mounts this into the VM as the project source.

If you do not have it yet:

```bash
git clone https://github.com/Peleke/openclaw.git ~/Projects/openclaw
```

## Optional: A Secrets File

If you want the agent to have access to API keys (Anthropic, OpenAI, GitHub, etc.), prepare a `.env` file:

```bash
cat > ~/.openclaw-secrets.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-xxx
GH_TOKEN=ghp_xxx
OPENCLAW_GATEWAY_PASSWORD=mypass
EOF
```

See the [Secrets configuration page](../configuration/secrets.md) for the full list of supported variables.

## Checklist

Before moving on to [Installation](installation.md), confirm:

- [x] Running macOS (Apple Silicon or Intel)
- [x] Homebrew installed (`brew --version` returns a version)
- [x] ~10 GB free disk space
- [x] A local clone of the OpenClaw repo (or you know where you will clone it)

Everything else is handled by the bootstrap script.
