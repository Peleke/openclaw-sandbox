# buildlog Integration

[buildlog](https://github.com/Peleke/buildlog-template) is a measurable learning loop for AI-assisted work. Every AI-assisted session produces decisions, corrections, and outcomes — almost all of it gets discarded. buildlog captures that signal, extracts patterns, and uses Thompson Sampling to prove which patterns actually reduce mistakes. Then it renders those proven patterns into agent instruction files (CLAUDE.md, .cursorrules, copilot-instructions.md).

**[Full documentation](https://peleke.github.io/buildlog-template/)** | **[GitHub](https://github.com/Peleke/buildlog-template)**

In the sandbox, buildlog runs as an ambient data capture layer — installed globally, MCP server always available, maximum capture by default.

## How It Works

```
Session Activity --> Trajectory Capture --> Seed Extraction --> Thompson Sampling --> Agent Rules
```

1. **Captures** structured trajectories from every coding session (commits, decisions, outcomes)
2. **Extracts** decision patterns ("seeds") — atomic observations like "always define interfaces before implementations" or "mock at the boundary, not the implementation"
3. **Selects** which patterns to surface using **Thompson Sampling** — each seed maintains a Beta posterior updated by observed outcomes, balancing exploration of untested rules against exploitation of proven ones
4. **Renders** selected rules to every agent format (CLAUDE.md, .cursorrules, copilot-instructions.md, etc.)
5. **Closes the loop** with experiments — measures Repeated Mistake Rate (RMR) across sessions for statistical evidence, not vibes

!!! tip "What else is in the box"
    Beyond the core loop: a **review gauntlet** with curated reviewer personas, **LLM-backed extraction** (Anthropic/OpenAI/Ollama), an **MCP server** so agents can query seeds and skills during sessions, and an **npm wrapper** for JS/TS projects. See the [full docs](https://peleke.github.io/buildlog-template/) for details.

## Pre-Configured MCP Server

buildlog is installed as a `uv tool` and its MCP server is registered globally via `buildlog init-mcp --global`. Claude Code has access to all buildlog MCP tools automatically -- no additional setup needed inside the VM.

The CLAUDE.md at `~/.claude/CLAUDE.md` is configured with three layers:

1. **Base CLAUDE.md** -- copied from your host (via `--claude-md` flag) or a minimal default
2. **buildlog standard instructions** -- appended by `buildlog init-mcp`
3. **Sandbox-specific aggressive policy** -- appended by the buildlog role

!!! note "Aggressive by design"
    The sandbox CLAUDE.md instructs agents to use buildlog for **everything** -- every commit, every decision, every correction. The philosophy: without capture, there is no learning. The sandbox is isolated, so maximum capture is safe.

## Installation Details

The buildlog role installs:

1. **uv** -- the fast Python package manager (from `astral.sh/uv/install.sh`)
2. **buildlog** -- installed as a uv tool with the `anthropic` extra for LLM-backed extraction

```bash
uv tool install buildlog[anthropic]
```

Both are installed under the Ansible user's home directory (`~/.local/bin/`).

## Ansible Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `buildlog_version` | `""` (latest) | Pin to a specific version |
| `buildlog_extras` | `anthropic` | Python extras (for LLM extraction) |
| `buildlog_host_claude_md_path` | `/mnt/provision/CLAUDE.md` | Path to host CLAUDE.md in the VM |

Override at bootstrap:

```bash
./bootstrap.sh --openclaw ~/Projects/openclaw -e "buildlog_version=0.5.0"
```

## Usage Commands

All commands run from the host via `limactl shell`:

### Check state

```bash
limactl shell openclaw-sandbox -- buildlog overview
```

Shows the current project state: active sessions, recent entries, reward signals, and extracted skills.

### Start a session

```bash
limactl shell openclaw-sandbox -- buildlog new my-feature
```

Creates a new journal entry for the session. All subsequent commits and actions are tracked under this entry.

### Commit (always use instead of raw git commit)

```bash
limactl shell openclaw-sandbox -- buildlog commit -m "feat: add feature"
```

Wraps `git commit` with automatic entry logging. This is the primary capture mechanism -- it records what changed, why, and the commit metadata.

!!! warning "Always use `buildlog commit` instead of `git commit`"
    Raw `git commit` bypasses trajectory capture. Using `buildlog commit` ensures every change is recorded for downstream learning.

### Run the review gauntlet

```bash
limactl shell openclaw-sandbox -- buildlog gauntlet
```

Loads reviewer personas and evaluates recent changes against them. Findings are logged and feed into the Thompson Sampling system.

### Extract and render skills

```bash
limactl shell openclaw-sandbox -- buildlog skills
```

Extracts patterns from captured trajectories and renders proven rules to agent instruction formats.

## MCP Tools Available to Agents

The buildlog MCP server provides tools that agents (Claude Code) can call directly during sessions:

| Tool | Purpose |
|------|---------|
| `buildlog_overview()` | Check project state |
| `buildlog_commit(message)` | Git commit with logging |
| `buildlog_entry_new(slug)` | Create journal entry |
| `buildlog_gauntlet_rules()` | Load reviewer personas |
| `buildlog_gauntlet_issues(issues)` | Process review findings |
| `buildlog_gauntlet_loop()` | Full gauntlet review cycle |
| `buildlog_log_reward(outcome)` | Record outcome (accepted/rejected) |
| `buildlog_log_mistake()` | Record a mistake for learning |
| `buildlog_skills()` | Extract patterns from entries |
| `buildlog_status()` | See extracted skills |
| `buildlog_promote(skill_ids)` | Surface skills to agent rules |

## Data Outputs

buildlog generates several data files used by downstream systems:

| File | Purpose |
|------|---------|
| `buildlog/*.md` | Journal entries (one per session) |
| `buildlog/.buildlog/reward_events.jsonl` | Reward signal history |
| `buildlog/.buildlog/promoted.json` | Skills promoted to agent rules |
| `buildlog/.buildlog/review_learnings.json` | Learnings from gauntlet reviews |

## Host CLI Setup

To use `claw` commands from your Mac to interact with the sandboxed gateway:

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
source ~/.openclaw/dotfiles/env.sh

# Then from host:
claw status   # Shows sandbox gateway status
claw tui      # Opens TUI connected to sandbox
```

## Troubleshooting

### buildlog command not found

```bash
# Check uv tools path is in PATH
limactl shell openclaw-sandbox -- echo $PATH | grep .local/bin

# Check buildlog is installed
limactl shell openclaw-sandbox -- uv tool list | grep buildlog

# Reinstall if needed
limactl shell openclaw-sandbox -- uv tool install buildlog[anthropic]
```

### MCP tools not available to agent

1. Check MCP registration: `limactl shell openclaw-sandbox -- buildlog mcp-test`
2. Verify `~/.claude/CLAUDE.md` exists and contains buildlog instructions
3. Re-run `buildlog init-mcp --global -y` if needed

### buildlog commit fails

1. Ensure you are in a git repository
2. Check that there are staged changes: `git status`
3. Verify buildlog can access the workspace: `buildlog overview`

## Further Reading

For deep dives beyond sandbox integration, see the [full buildlog documentation](https://peleke.github.io/buildlog-template/):

| Topic | Link |
|-------|------|
| Installation & setup | [Getting Started](https://peleke.github.io/buildlog-template/getting-started/installation/) |
| Core concepts (the problem, the claim, the metric) | [Concepts](https://peleke.github.io/buildlog-template/getting-started/concepts/) |
| CLI reference | [CLI Reference](https://peleke.github.io/buildlog-template/guides/cli-reference/) |
| MCP integration | [MCP Integration](https://peleke.github.io/buildlog-template/guides/mcp-integration/) |
| Running experiments | [Experiments](https://peleke.github.io/buildlog-template/guides/experiments/) |
| Review gauntlet | [Review Gauntlet](https://peleke.github.io/buildlog-template/guides/review-gauntlet/) |
| Multi-agent rendering | [Multi-Agent Setup](https://peleke.github.io/buildlog-template/guides/multi-agent/) |
| Design philosophy & limitations | [Philosophy](https://peleke.github.io/buildlog-template/philosophy/) |
