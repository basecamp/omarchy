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

## Before You Start

Search both open and closed issues and pull requests before filing or coding. An open bug may already define the expected scope, while a closed PR may contain a valid approach that only needs rebasing onto the current architecture.

```bash
gh issue list --repo basecamp/omarchy --state all --search '<terms>'
gh pr list --repo basecamp/omarchy --state all --search '<terms>'
```

Confirm the problem still exists on the latest upstream default branch and inspect active PRs that touch the same files. Also identify whether the root cause belongs in Omarchy or an upstream dependency; an Omarchy workaround is appropriate when its shipped defaults expose broken behavior and can fix it without hiding a broader upstream regression.

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

Fetch the latest upstream default branch and create a focused branch from that commit. Follow the repository's own `AGENTS.md` and every matching task guide before editing; they are authoritative for style, testing, and commit conventions.

Test in layers before publishing:

1. Add and run a focused regression test that exercises the real changed code, including alternate modes and fallbacks that must retain old behavior.
2. Run `./test/all` and resolve every failure attributable to the change.
3. Follow the repository's visual-verification guide for anything visible. Compositor-level shortcuts require the disposable VM acceptance harness and QMP keyboard input; in-session `wtype` does not prove a global Hyprland bind.

Keep commits atomic. Before staging, inspect `git status` and the complete diff, then stage only intended paths. Push the branch and open a draft PR with the root cause, user impact, validation performed, and `Fixes #...` when an issue exists. A visual fix should include before/after captures (see [`capture.md`](capture.md)).
