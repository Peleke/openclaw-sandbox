# GitHub CLI

The `gh` CLI is installed from the official GitHub APT repository, enabling the agent to interact with GitHub -- creating PRs, managing issues, calling the GitHub API, and more.

## Installation

The `gh-cli` Ansible role installs `gh` using the standard APT repository pattern:

1. Download the GPG key to `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
2. Add the APT source to `/etc/apt/sources.list.d/github-cli.list`
3. Install the `gh` package

This is the same GPG key + APT source pattern used by the Docker CE role. Installation is idempotent -- if `gh` is already installed, the role skips all steps.

### Disabling GitHub CLI

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw -e "gh_cli_enabled=false"
```

## Authentication: GH_TOKEN Flow

`gh` natively respects the `GH_TOKEN` environment variable. No `gh auth login` is needed. The token flows through the [secrets pipeline](secrets.md):

```
Host secrets file (GH_TOKEN=ghp_xxx)
  --> Ansible regex extraction
    --> /etc/openclaw/secrets.env (mode 0600)
      --> Gateway: EnvironmentFile=-/etc/openclaw/secrets.env
        --> Container: sandbox.docker.env.GH_TOKEN = ${GH_TOKEN}
```

### Setting Up Your Token

#### Option 1: Secrets file (recommended)

```bash
echo 'GH_TOKEN=ghp_your_token_here' >> ~/.openclaw-secrets.env

./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

#### Option 2: Direct injection

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw -e "secrets_github_token=ghp_your_token_here"
```

!!! tip "Token scopes"
    For full agent functionality, create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) with permissions for:

    - **Repository access:** the repos the agent will work with
    - **Permissions:** Contents (read/write), Pull requests (read/write), Issues (read/write)

## gh in the VM

`gh` is available directly in the VM for the gateway process and any SSH sessions:

```bash
# Check gh version
limactl shell openclaw-sandbox -- gh --version

# Check authentication (loads secrets from env)
limactl shell openclaw-sandbox -- bash -c 'source /etc/openclaw/secrets.env && gh auth status'

# Use gh directly
limactl shell openclaw-sandbox -- bash -c 'source /etc/openclaw/secrets.env && gh repo list --limit 5'
```

The gateway loads `GH_TOKEN` automatically via its `EnvironmentFile=` directive, so the agent's tool executions have access without manual sourcing.

## gh in Sandbox Containers

The sandbox role ensures `gh` is available inside Docker containers through the [image augmentation pattern](docker-sandbox.md#image-openclaw-sandboxbookworm-slim):

1. After the sandbox image is built, the role checks `docker run --rm <image> which gh`
2. If `gh` is missing, it layers a new Docker image on top with `gh` installed
3. The original image's `USER` is inspected and restored after augmentation

The `GH_TOKEN` environment variable is passed into containers via the `sandbox.docker.env` configuration in `openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "env": {
            "GH_TOKEN": "${GH_TOKEN}"
          }
        }
      }
    }
  }
}
```

!!! note "Conditional passthrough"
    The `GH_TOKEN` passthrough is only added to `openclaw.json` if the token exists in `/etc/openclaw/secrets.env`. If you bootstrap without a GitHub token, no phantom env var is configured in containers.

## Verification Commands

```bash
# Check gh is installed in VM
limactl shell openclaw-sandbox -- gh --version

# Check gh auth (requires GH_TOKEN in secrets)
limactl shell openclaw-sandbox -- bash -c 'source /etc/openclaw/secrets.env && gh auth status'

# Check gh exists in sandbox image
limactl shell openclaw-sandbox -- docker run --rm openclaw-sandbox:bookworm-slim which gh

# Check gh version in sandbox image
limactl shell openclaw-sandbox -- docker run --rm openclaw-sandbox:bookworm-slim gh --version

# Check GH_TOKEN passthrough in openclaw.json
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.env.GH_TOKEN' ~/.openclaw/openclaw.json
# Should output: "${GH_TOKEN}"

# Verify GH_TOKEN is in secrets
limactl shell openclaw-sandbox -- sudo grep -c '^GH_TOKEN=' /etc/openclaw/secrets.env
```

## Troubleshooting

### gh auth status fails

1. Verify the token is in secrets: `sudo grep GH_TOKEN /etc/openclaw/secrets.env`
2. Check the token is valid (not expired or revoked) on [github.com/settings/tokens](https://github.com/settings/tokens)
3. Ensure you are sourcing the secrets file before running `gh`: `source /etc/openclaw/secrets.env && gh auth status`

### gh not found in sandbox container

1. Check the sandbox image was built: `docker images | grep openclaw-sandbox`
2. Check augmentation happened: look for "Added gh CLI to sandbox image" in bootstrap output
3. Rebuild the image: re-run `./bootstrap.sh` (it will detect the missing `gh` and re-augment)

### gh commands fail with 403 in container

The token might not be passing through. Check:

1. `jq '.agents.defaults.sandbox.docker.env' ~/.openclaw/openclaw.json` -- should show `GH_TOKEN`
2. The gateway must be restarted after secrets change: `bilrost restart`
