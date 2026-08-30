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

Search the open PRs before writing a fix. The backlog is large enough that one
bug draws several independent fixes: the lock screen losing password focus
after suspend had four open PRs at once. A duplicate costs review time instead
of saving it.

```bash
gh pr list --repo basecamp/omarchy --state open --search "password focus in:title"
gh pr list --repo basecamp/omarchy --state open --search "lock screen suspend focus"
```

Search by symptom and again in a wider form — a PR describing the same area in
different words will not match the first query. When an open PR already covers
the change, add to that one rather than opening a competing one: confirm the
bug on your hardware, review the approach, or contribute a test it lacks.

Never develop against `/usr/share/omarchy`. Clone a working copy instead:

```bash
gh repo fork basecamp/omarchy --clone
cd omarchy
```

Follow the repository's own `AGENTS.md` for style, testing, and commit
conventions — it is the authority on contributions. Keep commits atomic, run
`./test/all` before pushing, and open the PR with `gh pr create`. A PR that
fixes a visual problem should include before/after captures (again, see
[`capture.md`](capture.md)).
