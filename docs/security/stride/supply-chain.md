# Supply Chain

The Bilrost pulls code and binaries from npm, apt, Homebrew, NodeSource, the Bun installer, Docker Hub, and Ubuntu cloud images. Every one of these is a trust decision we're making implicitly. A compromised dependency runs with full privileges before any of our sandbox controls are active.

This is not a solvable problem -- it's a managed one. Here's what we actually do, what we don't, and what's worth doing for a hobby project.

## Dependency Sources

| Source | What it provides | Verification | Install pattern |
|--------|-----------------|-------------|-----------------|
| **Ubuntu cloud images** | Base VM OS | SHA256 checksums from Canonical; Lima verifies digest if configured | Downloaded once at VM creation |
| **apt (Ubuntu repos)** | System packages (curl, git, ufw, build-essential) | GPG-signed packages from Canonical | Standard apt with signature verification |
| **apt (Docker repo)** | Docker CE | GPG key in `/etc/apt/keyrings/docker.gpg` | Official Docker apt repo, key downloaded with `creates:` guard |
| **apt (GitHub CLI repo)** | `gh` CLI | GPG key in `/etc/apt/keyrings/githubcli-archive-keyring.gpg` | Official GitHub apt repo |
| **NodeSource** | Node.js 22.x | Third-party apt repo, adds its own GPG key | `curl | bash` setup script adds repo, then `apt install nodejs` |
| **bun.sh** | Bun runtime | None | `curl -fsSL https://bun.sh/install \| bash` |
| **npm registry** | OpenClaw's JS dependencies | Lockfile pins versions; integrity hashes in lockfile | `bun install` in workspace |
| **Homebrew** | Lima, Ansible, jq, Tailscale (host-side) | Bottles are checksummed; formulae from GitHub | `brew bundle` from Brewfile |
| **pip** | MkDocs, uv (host-side tooling) | PyPI packages, no pinning | `pip install` / `uv tool install` |
| **Docker Hub / build** | Sandbox base image | Built locally from OpenClaw's `sandbox-setup.sh` | `docker build` inside VM |

## What's Actually Verified

!!! note "The good"
    - **apt packages** from Ubuntu, Docker, and GitHub repos are GPG-signed. A compromised mirror can't inject packages without the signing key.
    - **Lockfile** pins npm dependency versions and includes integrity hashes. `bun install` won't silently upgrade to a malicious version if the lockfile is committed and used.
    - **Homebrew bottles** include checksums. Formula changes go through GitHub PR review.
    - **Docker/GitHub CLI GPG keys** are downloaded with `creates:` guards so they're fetched once, not re-downloaded on every run.

!!! danger "The bad"
    - **Bun** is installed via `curl | bash` with no checksum verification, no version pinning. If `bun.sh` is compromised, you get a backdoored runtime.
    - **NodeSource** setup is also `curl | bash` into root. It adds a third-party apt source, which means all future Node.js updates flow through NodeSource's infrastructure.
    - **npm postinstall scripts** run automatically during `bun install` with full user privileges. Any transitive dependency can execute arbitrary code at install time.
    - **No SBOM**. We don't generate or track a software bill of materials. If a CVE drops for a transitive dependency, we have no fast way to check exposure.
    - **pip packages** are not pinned. MkDocs and build tooling could be silently upgraded.

## What a Compromise Looks Like

The most realistic supply chain attack path for this project:

1. A transitive npm dependency gets compromised (maintainer account takeover, typosquatting, or dependency confusion)
2. The malicious version includes a postinstall script that runs during `bun install`
3. At install time, the code runs as the VM user with full access to the workspace
4. It reads `/etc/openclaw/secrets.env` (if running during provisioning when the file exists) or drops a payload that runs later
5. Exfiltration over HTTPS to any domain (port 443 is allowed by UFW)

The blast radius is contained to the VM -- the host filesystem is not directly accessible from install-time code. But API keys, gateway credentials, and anything in the workspace are exposed.

## Gaps

**No postinstall script controls**. Bun supports `trustedDependencies` in `bunfig.toml` to allowlist which packages can run lifecycle scripts. We don't use this.

**No frozen lockfile enforcement**. The provisioning runs `bun install`, not `bun install --frozen-lockfile`. A modified lockfile could introduce new dependencies.

**No dependency scanning**. No `bun audit` or equivalent in CI. Known vulnerabilities in transitive dependencies go undetected.

**No Bun/NodeSource checksum verification**. Both are trust-on-first-download with no integrity check.

**No domain-level egress filtering**. UFW allows HTTPS to any destination. A compromised dependency can exfiltrate to any server on port 443. Domain-based filtering (via a proxy or DNS policy) would limit this, but adds significant complexity.

## What's Realistic

For a hobby project, there's a spectrum from "easy wins" to "not worth the complexity":

!!! tip "Worth doing"
    1. **`bun install --frozen-lockfile`** in provisioning. One flag. Prevents lockfile drift.
    2. **`trustedDependencies`** in `bunfig.toml`. Allowlist packages that actually need postinstall scripts; block the rest.
    3. **Pin Bun version** with a checksum in `bootstrap.sh` instead of `curl | bash`.
    4. **Run `bun audit`** as a CI check on PRs that touch `package.json` or the lockfile.

!!! note "Nice to have"
    1. **SBOM generation** via CycloneDX or similar. Useful when a CVE drops and you want to check exposure quickly.
    2. **Pin NodeSource version** or switch to a direct `.deb` download with checksum.
    3. **Pin pip dependencies** for docs tooling.

!!! note "Probably overkill"
    1. **Vendoring npm dependencies**. Full control, but massive repo bloat and manual update burden.
    2. **Domain-allowlist egress filtering**. Effective, but requires a DNS proxy or HTTP proxy in the VM. Complex to maintain.
    3. **Reproducible builds**. Great in theory. Enormous effort for a project this size.
    4. **Runtime integrity monitoring** (AIDE, osquery). Adds operational overhead that doesn't match the threat level.

The honest summary: our biggest supply chain risk is npm postinstall scripts running unchecked, and the fix (`trustedDependencies` + `--frozen-lockfile`) is about 10 minutes of work. The `curl | bash` pattern for Bun is ugly but the blast radius is limited to a VM we can recreate from scratch. Everything else is defense-in-depth that's valuable but not urgent.

## Cross-References

- [Threat Model](../threat-model.md) -- overall methodology and trust boundaries
- [Elevation of Privilege](./elevation-of-privilege.md) -- what happens after a supply chain compromise
- [Information Disclosure](./information-disclosure.md) -- secrets at risk from compromised dependencies
- [Tampering](./tampering.md) -- integrity of provisioning pipeline
