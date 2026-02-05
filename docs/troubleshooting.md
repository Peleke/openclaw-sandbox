# Troubleshooting

This page covers common issues, diagnostic commands, and recovery procedures for OpenClaw Sandbox.

---

## Quick Diagnostics

Before diving into specific issues, run these commands to get an overview of the system state:

```bash
# VM status
limactl list

# Gateway status
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway

# Firewall status
limactl shell openclaw-sandbox -- sudo ufw status verbose

# Overlay status
limactl shell openclaw-sandbox -- overlay-status

# Docker status
limactl shell openclaw-sandbox -- docker info
```

---

## VM Issues

### Check VM Status

```bash
limactl list
```

Expected output when healthy:

```
NAME               STATUS     SSH            CPUS    MEMORY    DISK      DIR
openclaw-sandbox   Running    127.0.0.1:0    4       8GiB      50GiB     ~/.lima/openclaw-sandbox
```

If the status shows `Stopped`, start it:

```bash
limactl start openclaw-sandbox
```

### VM Won't Start

**Symptom**: `limactl start openclaw-sandbox` fails or hangs.

Common causes:

1. **Lima not installed** -- run `brew install lima` or let `bootstrap.sh` handle it.
2. **Insufficient disk space** -- the VM needs ~10GB. Check with `df -h`.
3. **Port conflict** -- another VM or process is using the same SSH port. Check with `lsof -i :0` or stop other Lima instances.
4. **Corrupt VM state** -- delete and recreate (see [Nuclear Option](#nuclear-option-delete-and-recreate) below).

!!! tip
    If the VM is stuck in a bad state, try stopping it first: `limactl stop openclaw-sandbox`, then start again.

### Lima `cd` Warnings

**Symptom**: When running `limactl shell openclaw-sandbox`, you see warnings like:

```
bash: line 1: cd: /Users/you/Projects/openclaw-sandbox: No such file or directory
```

**This is benign.** Lima tries to `cd` to your host's current working directory inside the VM, but that path does not exist in the VM's filesystem. The shell session still works -- it just starts in the home directory instead.

You can ignore this warning entirely.

---

## Gateway Issues

### Gateway Not Running

**Symptom**: The agent cannot connect, or `claw status` shows the gateway as down.

Check the service status:

```bash
limactl shell openclaw-sandbox -- systemctl status openclaw-gateway
```

If the service is `inactive` or `failed`:

```bash
# Try starting it
limactl shell openclaw-sandbox -- sudo systemctl start openclaw-gateway

# Check if onboard has been run
limactl shell openclaw-sandbox -- test -f ~/.openclaw/openclaw.json && echo "Config exists" || echo "MISSING - run onboard"
```

If the config is missing, run the interactive onboard:

```bash
./bootstrap.sh --onboard
```

### View Gateway Logs

```bash
# Follow logs in real-time
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -f

# Last 50 lines
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -n 50

# Logs since last boot
limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -b

# Check application log
limactl shell openclaw-sandbox -- tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

### Gateway Crashes on Start

**Symptom**: Service starts then immediately exits.

Common causes:

1. **Missing secrets** -- the gateway needs at minimum an API key. Check `/etc/openclaw/secrets.env`.
2. **Bad config** -- invalid `openclaw.json`. Try removing and re-running onboard.
3. **Port conflict** -- something else is using port 18789.

```bash
# Check if port is in use
limactl shell openclaw-sandbox -- ss -tlnp | grep 18789

# Check secrets file exists and has content
limactl shell openclaw-sandbox -- sudo test -f /etc/openclaw/secrets.env && echo "EXISTS" || echo "MISSING"
```

---

## Firewall Issues

### Check Firewall Rules

```bash
limactl shell openclaw-sandbox -- sudo ufw status verbose
```

Expected output:

```
Status: active
Logging: on (low)
Default: deny (incoming), deny (outgoing), deny (routed)

To                         Action      From
--                         ------      ----
18789/tcp                  ALLOW IN    Anywhere
22/tcp                     ALLOW IN    Anywhere
443/tcp                    ALLOW OUT   Anywhere
80/tcp                     ALLOW OUT   Anywhere
53                         ALLOW OUT   Anywhere
123/udp                    ALLOW OUT   Anywhere
100.64.0.0/10              ALLOW OUT   Anywhere
41641/udp                  ALLOW OUT   Anywhere
```

!!! warning
    If `ufw status` shows `Status: inactive`, the firewall is not running. Re-provision the VM to fix: `./bootstrap.sh --openclaw ~/Projects/openclaw`.

### Agent Cannot Reach APIs

**Symptom**: LLM API calls fail with connection errors.

1. Check that HTTPS outbound is allowed:
    ```bash
    limactl shell openclaw-sandbox -- sudo ufw status | grep 443
    ```

2. Check DNS resolution:
    ```bash
    limactl shell openclaw-sandbox -- nslookup api.anthropic.com
    ```

3. Test HTTPS connectivity:
    ```bash
    limactl shell openclaw-sandbox -- curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com
    ```

---

## Secrets Issues

### Verify Secrets Loaded

```bash
limactl shell openclaw-sandbox -- sudo cat /etc/openclaw/secrets.env
```

You should see your secrets (API keys, tokens) listed. The file should have restricted permissions:

```bash
limactl shell openclaw-sandbox -- ls -la /etc/openclaw/secrets.env
# Expected: -rw------- 1 root root ... /etc/openclaw/secrets.env
```

### Secrets Not Available to Gateway

**Symptom**: Gateway starts but API calls fail with auth errors.

1. Verify the secrets file has the right key names:
    ```bash
    limactl shell openclaw-sandbox -- sudo grep ANTHROPIC /etc/openclaw/secrets.env
    ```

2. Check the gateway's systemd unit references the file:
    ```bash
    limactl shell openclaw-sandbox -- systemctl cat openclaw-gateway | grep EnvironmentFile
    # Expected: EnvironmentFile=/etc/openclaw/secrets.env
    ```

3. Restart the gateway to pick up changes:
    ```bash
    limactl shell openclaw-sandbox -- sudo systemctl restart openclaw-gateway
    ```

### Re-injecting Secrets

If you need to update secrets after initial bootstrap:

```bash
# Edit the secrets file on the host, then re-provision
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

!!! note
    Re-provisioning is safe and idempotent. It updates secrets without destroying the VM.

---

## Overlay Issues

### Check Overlay Status

```bash
# Using the VM helper
limactl shell openclaw-sandbox -- overlay-status

# Or check the mount directly
limactl shell openclaw-sandbox -- mountpoint -q /workspace && echo "Mounted" || echo "NOT mounted"

# See what's in the overlay upper layer (pending changes)
limactl shell openclaw-sandbox -- sudo ls /var/lib/openclaw/overlay/upper/
```

### Overlay Not Mounted

**Symptom**: `/workspace` is empty or shows the raw read-only mount.

```bash
# Check the systemd mount unit
limactl shell openclaw-sandbox -- systemctl status workspace.mount

# Try remounting
limactl shell openclaw-sandbox -- sudo systemctl restart workspace.mount
```

If the mount unit is missing, re-provision:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

### Overlay Fills Up

The overlay upper layer lives on the VM's disk. If it gets too large:

```bash
# Check overlay size
limactl shell openclaw-sandbox -- sudo du -sh /var/lib/openclaw/overlay/upper/

# Reset overlay (discards ALL writes)
limactl shell openclaw-sandbox -- sudo overlay-reset

# Or from host
./scripts/sync-gate.sh --reset
```

!!! warning
    `overlay-reset` discards all changes in the overlay. Sync any changes you want to keep first using `./scripts/sync-gate.sh`.

---

## Docker Issues

### Check Docker Status

```bash
# Docker daemon status
limactl shell openclaw-sandbox -- docker info

# Check sandbox image exists
limactl shell openclaw-sandbox -- docker images | grep openclaw-sandbox
```

Expected image output:

```
openclaw-sandbox   bookworm-slim   abc123   2 hours ago   250MB
```

### Docker Not Running

**Symptom**: `docker info` fails with "Cannot connect to the Docker daemon."

```bash
# Check Docker service
limactl shell openclaw-sandbox -- systemctl status docker

# Start Docker
limactl shell openclaw-sandbox -- sudo systemctl start docker
```

### Sandbox Image Missing

**Symptom**: `docker images | grep openclaw-sandbox` shows nothing.

The sandbox image is built during provisioning. Re-provision to rebuild it:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

### `gh` Missing from Sandbox Image

The sandbox image is augmented with `gh` during provisioning. Verify:

```bash
limactl shell openclaw-sandbox -- docker run --rm openclaw-sandbox:bookworm-slim gh --version
```

If `gh` is missing, re-provisioning will re-augment the image.

### Container Networking Issues

If containers cannot reach the internet:

```bash
# Check Docker network mode in config
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.network' ~/.openclaw/openclaw.json

# Test from inside a container
limactl shell openclaw-sandbox -- docker run --rm alpine wget -q -O- https://api.anthropic.com
```

!!! note
    If `network` is set to `"none"`, containers are fully isolated with no network access. This is intentional for maximum security. Change to `"bridge"` if containers need internet access.

---

## Sync Gate Issues

### Check Sync Status

```bash
# Show pending changes (dry run)
./scripts/sync-gate.sh --dry-run

# Check overlay status from host
./scripts/sync-gate.sh --status
```

### Sync Fails with Gitleaks Error

**Symptom**: `sync-gate.sh` refuses to sync, reporting a secret was found.

This means gitleaks detected what looks like a secret in the overlay changes. This is working as intended.

1. Review the flagged file:
    ```bash
    ./scripts/sync-gate.sh --dry-run
    ```

2. If it is a false positive, you may need to add a `.gitleaksignore` entry or fix the file.

3. If it is a real secret, remove it from the overlay:
    ```bash
    limactl shell openclaw-sandbox -- rm /var/lib/openclaw/overlay/upper/<path-to-file>
    ```

### Sync Fails with Path Allowlist Error

**Symptom**: `sync-gate.sh` rejects files outside the allowed paths.

The sync gate only copies files within the configured path allowlist. Files outside the allowlist are blocked intentionally. Check the sync gate configuration for the allowed paths.

---

## Tailscale Issues

### Test Tailscale Routing

```bash
limactl shell openclaw-sandbox -- ~/test-tailscale.sh 100.x.x.x
```

Replace `100.x.x.x` with an actual Tailscale IP on your network.

### Tailscale Traffic Blocked

Check that the UFW rules allow Tailscale:

```bash
limactl shell openclaw-sandbox -- sudo ufw status | grep -E "100.64|41641"
```

You should see:

```
100.64.0.0/10              ALLOW OUT   Anywhere
41641/udp                  ALLOW OUT   Anywhere
```

If these rules are missing, re-provision the VM.

---

## Obsidian Vault Issues

### Vault Not Visible in Containers

```bash
# Check if the overlay mount exists
limactl shell openclaw-sandbox -- mountpoint -q /workspace-obsidian && echo "Mounted" || echo "NOT mounted"

# Check sandbox bind config
limactl shell openclaw-sandbox -- jq '.agents.defaults.sandbox.docker.binds' ~/.openclaw/openclaw.json
```

If the mount is not present, ensure you bootstrapped with `--vault`:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --vault ~/Documents/Vaults/main
```

### Stale Obsidian Mounts After Re-provisioning Without `--vault`

If you previously used `--vault` and then re-provision without it, stale systemd mount units are automatically cleaned up. If you see errors related to stale mounts, re-provision:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw
```

---

## Re-provisioning

Most issues can be fixed by re-running `bootstrap.sh`. This is safe and idempotent:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

This will:

- Update Ansible roles without destroying the VM
- Re-apply firewall rules
- Re-inject secrets
- Rebuild the sandbox image if needed
- Clean up stale mounts

!!! tip
    Re-provisioning is the recommended first step for most issues. It is fast and non-destructive.

---

## Nuclear Option: Delete and Recreate

If nothing else works, delete the VM and start from scratch:

```bash
# Delete the VM completely
./bootstrap.sh --delete

# Recreate from scratch
./bootstrap.sh --openclaw ~/Projects/openclaw --secrets ~/.openclaw-secrets.env
```

!!! warning
    `--delete` destroys the VM and all data inside it, including any overlay changes that have not been synced to the host. Make sure to run `./scripts/sync-gate.sh` first if you have work to preserve.

This is also required when changing mount modes (e.g., switching between secure mode and `--yolo-unsafe`), because Lima bakes mount configurations at VM creation time.

### When to Use Nuclear Option

- VM is in a corrupt or unrecoverable state
- Switching between `--yolo-unsafe` and default (overlay) mode
- Major version upgrade that changes VM structure
- You just want a clean slate

---

## Getting Help

If none of the above resolves your issue:

1. Check the [GitHub Issues](https://github.com/Peleke/openclaw-sandbox/issues) for known problems.
2. Open a new issue with:
    - Output of `limactl list`
    - Output of `limactl shell openclaw-sandbox -- systemctl status openclaw-gateway`
    - Output of `limactl shell openclaw-sandbox -- sudo journalctl -u openclaw-gateway -n 50`
    - Your macOS version and architecture (`uname -m`)
    - The `bootstrap.sh` flags you used
