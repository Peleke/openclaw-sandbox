#!/usr/bin/env python3
"""
Test cadence.json.j2 template rendering for all conditional combinations.

Validates:
- All 4 runlist x githubWatcher combinations produce valid JSON
- vaultPath uses the merged overlay mount
- githubWatcher fields are correctly rendered
- Trailing comma handling is correct
"""

import json
import sys
from jinja2 import Environment

env = Environment()
env.filters["to_json"] = lambda v: json.dumps(v)
env.filters["bool"] = lambda v: bool(v)

TEMPLATE_PATH = "ansible/roles/cadence/templates/cadence.json.j2"

with open(TEMPLATE_PATH) as f:
    tmpl = env.from_string(f.read())

BASE_VARS = {
    "cadence_enabled": True,
    "cadence_vault_path": "/workspace-obsidian",
    "cadence_delivery_channel": "telegram",
    "cadence_telegram_chat_id": "123456",
    "user_home": "/home/peleke",
    "cadence_pillars": [
        {"id": "tech", "name": "Technology", "keywords": ["code", "ai"]},
    ],
    "cadence_llm_provider": "anthropic",
    "cadence_llm_model": "claude-haiku-4-5-20251001",
    "cadence_schedule_enabled": True,
    "cadence_nightly_digest": "21:00",
    "cadence_morning_standup": "08:00",
    "cadence_timezone": "America/New_York",
}

RUNLIST_VARS = {
    "cadence_runlist_enabled": True,
    "cadence_runlist_morning_time": "07:30",
    "cadence_runlist_nightly_time": "22:00",
    "cadence_runlist_dir": "Runlist",
}

GH_WATCHER_VARS = {
    "cadence_github_watcher_enabled": True,
    "cadence_github_watcher_owner": "Peleke",
    "cadence_github_watcher_scan_time": "21:00",
    "cadence_github_watcher_output_dir": "Buildlog",
    "cadence_github_watcher_max_buildlog_entries": 3,
    "cadence_github_watcher_exclude_repos": [],
}

passed = 0
failed = 0


def test(name, vars_dict, assertions):
    global passed, failed
    try:
        result = tmpl.render(**vars_dict)
        parsed = json.loads(result)
        for check_name, check_fn in assertions.items():
            assert check_fn(parsed), f"Assertion failed: {check_name}"
        passed += 1
        print(f"  PASS: {name}")
    except Exception as e:
        failed += 1
        print(f"  FAIL: {name} — {e}")


print("cadence.json.j2 template tests")
print("=" * 50)

# Test 1: Both runlist and githubWatcher enabled
test(
    "Both runlist + githubWatcher enabled",
    {**BASE_VARS, **RUNLIST_VARS, **GH_WATCHER_VARS},
    {
        "valid JSON": lambda p: True,
        "has runlist": lambda p: "runlist" in p,
        "has githubWatcher": lambda p: "githubWatcher" in p,
        "githubWatcher.enabled": lambda p: p["githubWatcher"]["enabled"] is True,
        "githubWatcher.owner": lambda p: p["githubWatcher"]["owner"] == "Peleke",
        "githubWatcher.scanTime": lambda p: p["githubWatcher"]["scanTime"] == "21:00",
        "githubWatcher.outputDir": lambda p: p["githubWatcher"]["outputDir"] == "Buildlog",
        "githubWatcher.maxBuildlogEntries": lambda p: p["githubWatcher"]["maxBuildlogEntries"] == 3,
        "githubWatcher.excludeRepos": lambda p: p["githubWatcher"]["excludeRepos"] == [],
        "vaultPath correct": lambda p: p["vaultPath"] == "/workspace-obsidian",
        "runlist.enabled": lambda p: p["runlist"]["enabled"] is True,
    },
)

# Test 2: Neither enabled
test(
    "Neither runlist nor githubWatcher enabled",
    {
        **BASE_VARS,
        "cadence_runlist_enabled": False,
        "cadence_github_watcher_enabled": False,
    },
    {
        "valid JSON": lambda p: True,
        "no runlist": lambda p: "runlist" not in p,
        "no githubWatcher": lambda p: "githubWatcher" not in p,
        "schedule present": lambda p: "schedule" in p,
    },
)

# Test 3: Only githubWatcher enabled
test(
    "Only githubWatcher enabled (no runlist)",
    {
        **BASE_VARS,
        "cadence_runlist_enabled": False,
        **GH_WATCHER_VARS,
    },
    {
        "valid JSON": lambda p: True,
        "no runlist": lambda p: "runlist" not in p,
        "has githubWatcher": lambda p: "githubWatcher" in p,
        "githubWatcher.owner": lambda p: p["githubWatcher"]["owner"] == "Peleke",
    },
)

# Test 4: Only runlist enabled
test(
    "Only runlist enabled (no githubWatcher)",
    {
        **BASE_VARS,
        **RUNLIST_VARS,
        "cadence_github_watcher_enabled": False,
    },
    {
        "valid JSON": lambda p: True,
        "has runlist": lambda p: "runlist" in p,
        "no githubWatcher": lambda p: "githubWatcher" not in p,
    },
)

# Test 5: Custom githubWatcher values
test(
    "Custom githubWatcher values",
    {
        **BASE_VARS,
        "cadence_runlist_enabled": False,
        "cadence_github_watcher_enabled": True,
        "cadence_github_watcher_owner": "MyOrg",
        "cadence_github_watcher_scan_time": "18:00",
        "cadence_github_watcher_output_dir": "Engineering",
        "cadence_github_watcher_max_buildlog_entries": 5,
        "cadence_github_watcher_exclude_repos": ["fork-repo", "archived-repo"],
    },
    {
        "valid JSON": lambda p: True,
        "custom owner": lambda p: p["githubWatcher"]["owner"] == "MyOrg",
        "custom scanTime": lambda p: p["githubWatcher"]["scanTime"] == "18:00",
        "custom outputDir": lambda p: p["githubWatcher"]["outputDir"] == "Engineering",
        "custom maxEntries": lambda p: p["githubWatcher"]["maxBuildlogEntries"] == 5,
        "custom excludeRepos": lambda p: p["githubWatcher"]["excludeRepos"] == [
            "fork-repo",
            "archived-repo",
        ],
    },
)

# Test 6: No telegram chat ID (conditional field)
test(
    "No telegram chat ID",
    {
        **BASE_VARS,
        "cadence_telegram_chat_id": "",
        "cadence_runlist_enabled": False,
        "cadence_github_watcher_enabled": False,
    },
    {
        "valid JSON": lambda p: True,
        "no telegramChatId": lambda p: "telegramChatId" not in p["delivery"],
    },
)

# Test 7: vaultPath uses overlay_obsidian_path default
test(
    "vaultPath uses merged overlay mount",
    {
        **BASE_VARS,
        "cadence_runlist_enabled": False,
        "cadence_github_watcher_enabled": False,
    },
    {
        "vaultPath is /workspace-obsidian": lambda p: p["vaultPath"]
        == "/workspace-obsidian",
        "vaultPath is NOT raw upper": lambda p: "overlay" not in p["vaultPath"],
    },
)

print()
print(f"Results: {passed} passed, {failed} failed")
if failed > 0:
    sys.exit(1)
print("ALL TESTS PASSED")
