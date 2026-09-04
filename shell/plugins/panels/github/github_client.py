#!/usr/bin/python3

"""Fetch a bounded, read-only GitHub maintainer dashboard through gh."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse


MAX_OUTPUT_BYTES = 4 * 1024 * 1024
COMMAND_TIMEOUT_SECONDS = 25
ITEM_LIMIT = 30
REPOSITORY_LIMIT = 16
DISCUSSION_LIMIT = 4

QUERY = r"""
query OmarchyGitHub($issueQuery: String!, $prQuery: String!, $reviewQuery: String!, $repoCount: Int!, $discussionCount: Int!) {
  viewer {
    login
    repositories(first: $repoCount, orderBy: {field: PUSHED_AT, direction: DESC}, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], isFork: false) {
      nodes {
        nameWithOwner
        url
        pushedAt
        defaultBranchRef {
          name
          target {
            ... on Commit {
              oid
              committedDate
              statusCheckRollup { state }
            }
          }
        }
        discussions(first: $discussionCount, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            number
            title
            url
            updatedAt
            bodyText
            comments { totalCount }
            category { name }
            author { login }
          }
        }
      }
    }
  }
  issues: search(first: 30, type: ISSUE, query: $issueQuery) {
    nodes {
      ... on Issue {
        number
        title
        url
        updatedAt
        bodyText
        repository { nameWithOwner }
        author { login }
        labels(first: 4) { nodes { name color } }
      }
    }
  }
  pullRequests: search(first: 30, type: ISSUE, query: $prQuery) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        updatedAt
        bodyText
        isDraft
        reviewDecision
        repository { nameWithOwner }
        author { login }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
  reviewRequests: search(first: 30, type: ISSUE, query: $reviewQuery) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        updatedAt
        bodyText
        isDraft
        reviewDecision
        repository { nameWithOwner }
        author { login }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
}
"""


class GhError(RuntimeError):
    def __init__(self, message: str, kind: str = "fetch") -> None:
        super().__init__(message)
        self.kind = kind


Runner = Callable[[list[str]], str]


def state_path() -> Path:
    root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return root / "omarchy/github/dashboard.json"


def run_command(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=False,
            timeout=COMMAND_TIMEOUT_SECONDS,
            env={**os.environ, "GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"},
        )
    except FileNotFoundError as error:
        raise GhError("Install GitHub CLI to use this panel", "missing-gh") from error
    except subprocess.TimeoutExpired as error:
        raise GhError("GitHub took too long to respond", "timeout") from error

    stdout = result.stdout[: MAX_OUTPUT_BYTES + 1]
    stderr = result.stderr[:8192]
    if len(stdout) > MAX_OUTPUT_BYTES:
        raise GhError("GitHub returned more data than this panel can safely display", "response-limit")
    if result.returncode != 0:
        message = stderr.decode("utf-8", "replace").strip()
        lowered = message.lower()
        if "auth login" in lowered or "authentication" in lowered or "not logged" in lowered:
            raise GhError("Sign in with gh auth login to use this panel", "auth")
        if "resource not accessible" in lowered or "insufficient" in lowered or "scope" in lowered:
            raise GhError("GitHub access is missing a required read scope", "permission")
        raise GhError(clean_error(message) or "GitHub could not be refreshed")
    return stdout.decode("utf-8", "replace")


def clean_error(message: str) -> str:
    value = " ".join(str(message or "").split())
    return value[:177] + "…" if len(value) > 180 else value


def safe_web_url(value: Any) -> str:
    url = str(value or "")
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.username or parsed.password:
        return ""
    if (parsed.hostname or "").lower() != "github.com" or parsed.port not in (None, 443):
        return ""
    return url


def api_url_to_web(value: Any, fallback: str) -> str:
    url = str(value or "")
    prefix = "https://api.github.com/repos/"
    if not url.startswith(prefix):
        return fallback
    path = url[len(prefix) :]
    path = path.replace("/pulls/", "/pull/")
    candidate = "https://github.com/" + path
    return safe_web_url(candidate) or fallback


def clipped(value: Any, limit: int = 1600) -> str:
    text = " ".join(str(value or "").replace("\x00", "").split())
    return text[:limit]


def load_json(raw: str, label: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise GhError(f"GitHub returned invalid {label} data", "parse") from error


def labels(nodes: Any) -> list[dict[str, str]]:
    result = []
    for node in (nodes or [])[:4]:
        result.append({"name": clipped(node.get("name"), 40), "color": clipped(node.get("color"), 6)})
    return result


def status_from_pr(node: dict[str, Any]) -> str:
    commits = ((node.get("commits") or {}).get("nodes") or [])
    if not commits:
        return "UNKNOWN"
    return str((((commits[-1].get("commit") or {}).get("statusCheckRollup") or {}).get("state") or "UNKNOWN"))


def issue_item(node: dict[str, Any]) -> dict[str, Any]:
    repository = node.get("repository") or {}
    return {
        "id": f"issue:{repository.get('nameWithOwner', '')}:{node.get('number', '')}",
        "kind": "issue",
        "repo": clipped(repository.get("nameWithOwner"), 120),
        "number": int(node.get("number") or 0),
        "title": clipped(node.get("title"), 300),
        "body": clipped(node.get("bodyText")),
        "url": safe_web_url(node.get("url")),
        "updatedAt": clipped(node.get("updatedAt"), 40),
        "author": clipped((node.get("author") or {}).get("login"), 80),
        "labels": labels(((node.get("labels") or {}).get("nodes") or [])),
        "lane": "Assigned",
    }


def pull_request_item(node: dict[str, Any], lane: str) -> dict[str, Any]:
    repository = node.get("repository") or {}
    return {
        "id": f"pr:{repository.get('nameWithOwner', '')}:{node.get('number', '')}",
        "kind": "pull-request",
        "repo": clipped(repository.get("nameWithOwner"), 120),
        "number": int(node.get("number") or 0),
        "title": clipped(node.get("title"), 300),
        "body": clipped(node.get("bodyText")),
        "url": safe_web_url(node.get("url")),
        "updatedAt": clipped(node.get("updatedAt"), 40),
        "author": clipped((node.get("author") or {}).get("login"), 80),
        "lane": lane,
        "draft": node.get("isDraft") is True,
        "reviewDecision": clipped(node.get("reviewDecision"), 40),
        "state": status_from_pr(node),
    }


def discussion_items(repositories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for repository in repositories:
        name = clipped(repository.get("nameWithOwner"), 120)
        for node in ((repository.get("discussions") or {}).get("nodes") or []):
            result.append({
                "id": f"discussion:{name}:{node.get('number', '')}",
                "kind": "discussion",
                "repo": name,
                "number": int(node.get("number") or 0),
                "title": clipped(node.get("title"), 300),
                "body": clipped(node.get("bodyText")),
                "url": safe_web_url(node.get("url")),
                "updatedAt": clipped(node.get("updatedAt"), 40),
                "author": clipped((node.get("author") or {}).get("login"), 80),
                "lane": clipped((node.get("category") or {}).get("name"), 80) or "Discussion",
                "comments": int((node.get("comments") or {}).get("totalCount") or 0),
            })
    return sorted(result, key=lambda item: item["updatedAt"], reverse=True)[:ITEM_LIMIT]


def ci_items(repositories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for repository in repositories:
        branch = repository.get("defaultBranchRef") or {}
        commit = branch.get("target") or {}
        rollup = commit.get("statusCheckRollup") or {}
        state = str(rollup.get("state") or "UNKNOWN")
        if not branch:
            continue
        result.append({
            "id": f"ci:{repository.get('nameWithOwner', '')}",
            "kind": "ci",
            "repo": clipped(repository.get("nameWithOwner"), 120),
            "title": f"{clipped(branch.get('name'), 80)} · {clipped(commit.get('oid'), 8)}",
            "body": "Latest default-branch status check rollup.",
            "url": safe_web_url(repository.get("url")) + "/actions" if safe_web_url(repository.get("url")) else "",
            "updatedAt": clipped(commit.get("committedDate"), 40),
            "lane": "Default branch",
            "state": state,
        })
    priority = {"FAILURE": 0, "ERROR": 0, "PENDING": 1, "EXPECTED": 1, "SUCCESS": 2, "UNKNOWN": 3}
    return sorted(result, key=lambda item: (priority.get(item["state"], 3), item["repo"]))


def notification_items(nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for node in nodes[:ITEM_LIMIT]:
        repository = node.get("repository") or {}
        fallback = safe_web_url(repository.get("html_url"))
        subject = node.get("subject") or {}
        result.append({
            "id": f"notification:{node.get('id', '')}",
            "kind": "notification",
            "repo": clipped(repository.get("full_name"), 120),
            "title": clipped(subject.get("title"), 300),
            "body": "Open the thread on GitHub to read the latest activity.",
            "url": api_url_to_web(subject.get("url"), fallback),
            "updatedAt": clipped(node.get("updated_at"), 40),
            "lane": clipped(node.get("reason"), 80).replace("_", " ").title(),
            "subjectType": clipped(subject.get("type"), 40),
            "unread": node.get("unread") is True,
        })
    return result


def fetch_dashboard(runner: Runner = run_command) -> dict[str, Any]:
    variables = [
        "-F", f"repoCount={REPOSITORY_LIMIT}",
        "-F", f"discussionCount={DISCUSSION_LIMIT}",
        "-f", "issueQuery=is:issue is:open assignee:@me archived:false sort:updated-desc",
        "-f", "prQuery=is:pr is:open author:@me archived:false sort:updated-desc",
        "-f", "reviewQuery=is:pr is:open review-requested:@me archived:false sort:updated-desc",
    ]
    graph = load_json(runner(["gh", "api", "graphql", "-f", f"query={QUERY}", *variables]), "dashboard")
    graph_errors = graph.get("errors") or []
    if graph_errors and not graph.get("data"):
        message = clipped((graph_errors[0] or {}).get("message"), 180)
        raise GhError(message or "GitHub could not build the dashboard")
    data = graph.get("data") or {}
    viewer = data.get("viewer") or {}
    repositories = ((viewer.get("repositories") or {}).get("nodes") or [])
    issues = [issue_item(node) for node in ((data.get("issues") or {}).get("nodes") or []) if node]
    authored = [pull_request_item(node, "Authored") for node in ((data.get("pullRequests") or {}).get("nodes") or []) if node]
    requested = [pull_request_item(node, "Review requested") for node in ((data.get("reviewRequests") or {}).get("nodes") or []) if node]
    pull_requests = []
    seen = set()
    for item in requested + authored:
        if item["id"] in seen:
            continue
        seen.add(item["id"])
        pull_requests.append(item)

    partial = bool(graph_errors)
    error = clipped((graph_errors[0] or {}).get("message"), 180) if graph_errors else ""
    try:
        notifications_raw = runner(["gh", "api", "notifications?all=false&participating=false&per_page=30"])
        notifications = notification_items(load_json(notifications_raw, "notification"))
    except GhError as notification_error:
        notifications = []
        partial = True
        error = clean_error(str(notification_error))

    return {
        "ok": True,
        "viewer": clipped(viewer.get("login"), 80),
        "fetchedAt": datetime.now(timezone.utc).isoformat(),
        "partial": partial,
        "stale": False,
        "error": error,
        "notifications": notifications,
        "issues": issues[:ITEM_LIMIT],
        "pullRequests": pull_requests[:ITEM_LIMIT],
        "discussions": discussion_items(repositories),
        "ci": ci_items(repositories),
    }


def atomic_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix="dashboard.", suffix=".tmp", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def cached_failure(error: GhError) -> dict[str, Any]:
    path = state_path()
    try:
        cached = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"ok": False, "errorKind": error.kind, "error": str(error), "stale": False}
    cached["ok"] = True
    cached["stale"] = True
    cached["partial"] = True
    cached["errorKind"] = error.kind
    cached["error"] = str(error)
    return cached


def main() -> int:
    if shutil.which("gh") is None:
        error = GhError("Install GitHub CLI to use this panel", "missing-gh")
        print(json.dumps(cached_failure(error)))
        return 0
    try:
        result = fetch_dashboard()
        atomic_write(state_path(), result)
    except GhError as error:
        result = cached_failure(error)
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
