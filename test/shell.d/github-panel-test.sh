#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT/shell/plugins/panels/github/github_client.py" <<'PY'
import importlib.util
import json
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("github_client", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

graph = {
    "data": {
        "viewer": {
            "login": "tom",
            "repositories": {
                "nodes": [
                    {
                        "nameWithOwner": "tom/project",
                        "url": "https://github.com/tom/project",
                        "pushedAt": "2026-09-04T07:00:00Z",
                        "defaultBranchRef": {
                            "name": "main",
                            "target": {
                                "oid": "abcdef123456",
                                "committedDate": "2026-09-04T07:00:00Z",
                                "statusCheckRollup": {"state": "FAILURE"},
                            },
                        },
                        "discussions": {
                            "nodes": [
                                {
                                    "number": 7,
                                    "title": "Native panel ideas",
                                    "url": "https://github.com/tom/project/discussions/7",
                                    "updatedAt": "2026-09-04T06:00:00Z",
                                    "bodyText": "A useful discussion body.",
                                    "comments": {"totalCount": 3},
                                    "category": {"name": "Ideas"},
                                    "author": {"login": "friend"},
                                }
                            ]
                        },
                    }
                ]
            },
        },
        "issues": {
            "nodes": [
                {
                    "number": 12,
                    "title": "Fix the thing",
                    "url": "https://github.com/tom/project/issues/12",
                    "updatedAt": "2026-09-04T05:00:00Z",
                    "bodyText": "Issue body",
                    "repository": {"nameWithOwner": "tom/project"},
                    "author": {"login": "friend"},
                    "labels": {"nodes": [{"name": "bug", "color": "ff0000"}]},
                }
            ]
        },
        "pullRequests": {
            "nodes": [
                {
                    "number": 18,
                    "title": "Ship it",
                    "url": "https://github.com/tom/project/pull/18",
                    "updatedAt": "2026-09-04T04:00:00Z",
                    "bodyText": "PR body",
                    "isDraft": False,
                    "reviewDecision": "APPROVED",
                    "repository": {"nameWithOwner": "tom/project"},
                    "author": {"login": "tom"},
                    "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
                }
            ]
        },
        "reviewRequests": {
            "nodes": [
                {
                    "number": 22,
                    "title": "Needs review",
                    "url": "https://github.com/other/project/pull/22",
                    "updatedAt": "2026-09-04T03:00:00Z",
                    "bodyText": "Review this",
                    "isDraft": False,
                    "reviewDecision": None,
                    "repository": {"nameWithOwner": "other/project"},
                    "author": {"login": "contributor"},
                    "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "PENDING"}}}]},
                },
                {
                    "number": 18,
                    "title": "Ship it",
                    "url": "https://github.com/tom/project/pull/18",
                    "updatedAt": "2026-09-04T04:00:00Z",
                    "bodyText": "PR body",
                    "isDraft": False,
                    "reviewDecision": "APPROVED",
                    "repository": {"nameWithOwner": "tom/project"},
                    "author": {"login": "tom"},
                    "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
                },
            ]
        },
    }
}

notifications = [
    {
        "id": "99",
        "unread": True,
        "reason": "review_requested",
        "updated_at": "2026-09-04T02:00:00Z",
        "repository": {
            "full_name": "other/project",
            "html_url": "https://github.com/other/project",
        },
        "subject": {
            "title": "Please review",
            "type": "PullRequest",
            "url": "https://api.github.com/repos/other/project/pulls/22",
        },
    }
]

commands = []

def runner(command):
    commands.append(command)
    if command[:3] == ["gh", "api", "graphql"]:
        return json.dumps(graph)
    if command == ["gh", "api", "notifications?all=false&participating=false&per_page=30"]:
        return json.dumps(notifications)
    raise AssertionError(command)

result = module.fetch_dashboard(runner)
assert result["ok"] is True
assert result["viewer"] == "tom"
assert len(result["issues"]) == 1
assert result["issues"][0]["labels"] == [{"name": "bug", "color": "ff0000"}]
assert [item["lane"] for item in result["pullRequests"]] == ["Review requested", "Review requested"]
assert len(result["pullRequests"]) == 2, "duplicate PRs must collapse"
assert result["pullRequests"][0]["state"] == "PENDING"
assert result["discussions"][0]["comments"] == 3
assert result["ci"][0]["state"] == "FAILURE"
assert result["notifications"][0]["url"] == "https://github.com/other/project/pull/22"
assert module.safe_web_url("javascript:alert(1)") == ""
assert module.safe_web_url("https://attacker@github.com/tom/project") == ""
assert module.safe_web_url("https://github.example/tom/project") == ""
assert module.safe_web_url("https://github.com/tom/project") == "https://github.com/tom/project"
assert any("discussionCount=4" in value for value in commands[0])

def partial_runner(command):
    if command[:3] == ["gh", "api", "graphql"]:
        return json.dumps(graph)
    raise module.GhError("missing notifications scope", "permission")

partial = module.fetch_dashboard(partial_runner)
assert partial["ok"] is True
assert partial["partial"] is True
assert partial["errorKind"] == "permission"
assert partial["notifications"] == []
assert partial["issues"], "a notification permission failure must preserve other data"

def graph_error_runner(command):
    return json.dumps({"errors": [{"message": "GraphQL schema rejected the request"}]})

try:
    module.fetch_dashboard(graph_error_runner)
    raise AssertionError("a GraphQL failure was accepted as an empty dashboard")
except module.GhError as error:
    assert "schema rejected" in str(error)

print(json.dumps(result, sort_keys=True))
PY

[[ -f $ROOT/shell/plugins/panels/github/manifest.json ]] || fail "GitHub panel manifest exists"
jq -e '
  .schemaVersion == 1 and
  .id == "omarchy.github" and
  .kinds == ["panel", "service"] and
  .keepLoaded == true and
  .entryPoints.panel == "Panel.qml" and
  .entryPoints.service == "Service.qml"
' "$ROOT/shell/plugins/panels/github/manifest.json" >/dev/null || fail "GitHub is a persistent first-party panel and service"

grep -qF 'implicitWidth: 1180' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub uses a desktop-sized native window"
grep -qF '"INBOX"' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub exposes an inbox view"
grep -qF '"ISSUES"' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub exposes assigned issues"
grep -qF '"PULL REQUESTS"' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub exposes pull requests"
grep -qF '"DISCUSSIONS"' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub exposes repository discussions"
grep -qF '"CI"' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub exposes default-branch CI"
grep -qF 'function sectionNeedsAttention(index)' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub navigation distinguishes attention from raw counts"
grep -qF 'Accessible.role: Accessible.ListItem' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub work items expose list semantics"
grep -qF 'if (!/^https:\/\/github\.com\//.test(url)) return' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub refuses non-GitHub browser handoffs"
grep -qF 'event.key >= Qt.Key_1 && event.key <= Qt.Key_5' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub views have direct keyboard shortcuts"
grep -qF 'readonly property bool compactMode: window.width < 980' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub preserves its navigation and list on compact windows"
grep -qF '"GH_PROMPT_DISABLED": "1"' "$ROOT/shell/plugins/panels/github/github_client.py" ||
  fail "GitHub helper never opens an authentication prompt behind the panel"
grep -qF 'gh auth refresh -h github.com -s notifications' "$ROOT/shell/plugins/panels/github/Panel.qml" ||
  fail "GitHub explains how to recover a missing notifications scope"
grep -qF 'MAX_OUTPUT_BYTES = 4 * 1024 * 1024' "$ROOT/shell/plugins/panels/github/github_client.py" ||
  fail "GitHub helper bounds command output"
grep -qF 'o.bind("SUPER + ALT + I", "GitHub", "omarchy-shell shell toggle omarchy.github")' "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "GitHub has a native desktop shortcut"
grep -qF '"trigger.github": {"icon":"","label":"GitHub","action":"omarchy-shell shell toggle omarchy.github"}' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "GitHub is discoverable in the native Trigger menu"

pass "GitHub helper normalizes bounded read-only maintainer data"
pass "GitHub panel covers inbox, issues, pull requests, discussions, and CI"
pass "GitHub attention rail and keyboard navigation are present"
