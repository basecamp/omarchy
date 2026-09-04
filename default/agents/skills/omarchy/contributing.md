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

## Verify Before Filing

A duplicate or already-fixed report costs a maintainer more time than no
report at all. Before drafting anything, confirm all three:

1. **It reproduces against the exact installed version, on the matching
   upstream tag** — not just the default branch, since an unreleased fix
   there wouldn't apply to what's actually installed, and a fix already
   released after the installed version means it's not a live bug either.
   `omarchy version` doesn't necessarily match a release tag verbatim (it may
   carry a packaging suffix, e.g. `4.0.0-1` for tag `v4.0.0`), so look up the
   matching tag rather than assuming a `v<version>` prefix:
   ```bash
   omarchy version
   gh release list --repo basecamp/omarchy   # find the matching tag
   curl -fsSL "https://raw.githubusercontent.com/basecamp/omarchy/<tag>/<path>"
   # diff that against the local file/behavior
   ```
2. **No existing issue already covers it** — search open *and* closed. A
   closed-as-fixed issue that still reproduces on the current release is a
   regression worth reporting; a closed-as-not-a-bug issue on the same
   symptom (e.g. a stale local dependency, not an Omarchy bug) means don't
   file at all.
   ```bash
   gh issue list --repo basecamp/omarchy --state all --search "<keywords>"
   ```
3. **No pull request already fixes it**, open or merged. A merged-but-unreleased
   PR means the fix is on the default branch and will ship in the next
   release — not installable yet via `omarchy update`, so only worth a new
   report if it still reproduces after that release ships. An open PR means
   point the user at it instead of filing a duplicate.
   ```bash
   gh pr list --repo basecamp/omarchy --state all --search "<keywords>"
   ```

Only proceed to drafting a report once all three come back clean.

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
conventions — it is the authority on contributions. Keep commits atomic, run
`./test/all` before pushing, and open the PR with `gh pr create`. A PR that
fixes a visual problem should include before/after captures (again, see
[`capture.md`](capture.md)).
