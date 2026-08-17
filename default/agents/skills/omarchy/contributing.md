# Reporting Issues and Submitting PRs

Read this when the user wants to diagnose or report an Omarchy bug, suggest a
feature, or explicitly contribute a fix upstream.

## Keep Upstream Work Explicit

Reporting or diagnosing a bug does not authorize implementing a fix. Do not
leave the current project or clone, fork, branch, or modify an Omarchy source
checkout unless the user explicitly asks to work on an upstream Omarchy fix.

If upstream work is explicitly requested but the current project is not an
Omarchy source checkout, tell the user that the work requires a separate
checkout and get confirmation before creating one. Once working in an Omarchy
source checkout, follow its repository instructions.

Omarchy lives at https://github.com/basecamp/omarchy. Route requests to the
right place:

- **Verified bugs** -> GitHub issues. Issues are for validated bugs only, not
  support requests.
- **Feature ideas and suggestions** ->
  https://github.com/basecamp/omarchy/discussions/categories/suggestions
- **Support and "is this a bug?" questions** -> the Discord community at
  https://omarchy.org/discord. Start here when the problem isn't clearly a bug
  in Omarchy itself.

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

Only follow this workflow when the user explicitly asks to implement or prepare
an upstream Omarchy fix. Never develop against `/usr/share/omarchy`. Use an
existing Omarchy source checkout when one is available. If a new checkout is
needed, explain that to the user and get confirmation before creating it:

```bash
gh repo fork basecamp/omarchy --clone
cd omarchy
```

Follow the repository's own `AGENTS.md` for style, testing, and commit
conventions — it is the authority on contributions. Keep commits atomic and run
`./test/all` before pushing. Preparing a fix does not authorize publishing it;
get the user's explicit approval before pushing or opening the PR with
`gh pr create`. A PR that fixes a visual problem should include before/after
captures (again, see [`capture.md`](capture.md)).
