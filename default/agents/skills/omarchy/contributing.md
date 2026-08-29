# Reporting Issues and Submitting PRs

Read this when the user wants to report an Omarchy bug, suggest a feature, or
contribute a fix upstream.

Omarchy lives at https://github.com/basecamp/omarchy. Route requests to the
right place:

- **Verified bugs** -> GitHub issues. Issues are for validated bugs only, not
  support requests.
- **Feature ideas and suggestions** ->
  https://github.com/basecamp/omarchy/discussions/categories/suggestions
- **Support and "is this a bug?" questions** -> the Discord community at
  https://omarchy.org/discord. Start here when the problem isn't clearly a bug
  in Omarchy itself.

## Check It Isn't Already Known

Search issues **and** pull requests before writing anything up. An open PR
often already fixes the bug, and it is easy to miss when only issues are
searched:

```bash
gh search issues --repo basecamp/omarchy "<keywords>" --limit 10
gh search prs --repo basecamp/omarchy "<keywords>" --limit 10
```

If a PR is already open, add to that discussion instead of filing again.

## Verify Against the Default Branch

Check the bug against the branch development actually happens on. A fresh
`git clone` lands there, but an older checkout or a raw URL pinned to
`master` does not — `master` can be weeks behind a shipped release, so a bug
"confirmed" there may already be fixed, or the code may not match what users
are running:

```bash
gh repo view basecamp/omarchy --json defaultBranchRef --jq .defaultBranchRef.name
```

Compare against the installed copy in `$OMARCHY_PATH` too; when they agree,
the bug is current.

## Filing a Good Bug Report

The bug template asks for system details (CPU, GPU, Omarchy version), a
description with steps to reproduce, and diagnostics. Gather them:

```bash
omarchy version

# Generate the diagnostic log (also written to /tmp/omarchy-debug.log)
omarchy debug --no-sudo --print

# Interactive variant: `omarchy debug` offers to upload the log to
# logs.omarchy.org (expires after 24h) and prints a shareable URL to
# include in the issue.
```

**Capture the problem on screen.** A screenshot or short recording of the bug
is often worth more than the description — see [`capture.md`](capture.md) for
`omarchy capture screenshot` and `omarchy screenrecord`. Keep recordings short
and focused on the misbehavior. GitHub issue attachments are added by
drag-and-drop in the web form, so save the capture and hand the user the file
path to attach (`gh` cannot upload media).

For screen-recording failures specifically, rerun with
`OMARCHY_SCREENRECORD_DEBUG=true` and attach `/tmp/omarchy-screenrecord.log`.

File the issue with `gh` when available:

```bash
gh issue create --repo basecamp/omarchy --title "..." --body "..."
```

Include: what happened, what was expected, steps to reproduce, system details,
the debug log URL (or attached log), and the capture.

## Submitting a PR

Never develop against `/usr/share/omarchy`. Clone a working copy instead:

```bash
gh repo fork basecamp/omarchy --clone
cd omarchy
```

Follow the repository's own `AGENTS.md` for style, testing, and commit
conventions — it is the authority on contributions. Keep commits atomic and
open the PR with `gh pr create`. A PR that fixes a visual problem should
include before/after captures (again, see [`capture.md`](capture.md)).

For tests, `AGENTS.md` asks for the focused suite covering the area changed —
`./test/cli` or `./test/shell` — rather than `./test/all`. Run `./test/all`
too if you like, but treat unrelated failures as a signal about the machine
rather than the change: parts of it depend on the local environment, such as
attached-monitor counts or a sibling checkout, and can fail on a clean tree.
Confirm by stashing the change (`git stash -u`, so new files go too) and
re-running, then `git stash pop` and say what you ran in the PR.
