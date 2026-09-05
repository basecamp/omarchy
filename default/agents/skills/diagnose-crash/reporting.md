# Reporting a Crash Upstream to Omarchy

Read this only after concluding that a crash is genuinely Omarchy's to fix.

## Is it even Omarchy's bug?

Be strict here. Omarchy is a configuration layer over Arch Linux, so a crash
inside a third-party application — a file manager, a browser, a GNOME or Qt
library — is almost always an upstream bug in **that** project, not in Omarchy.

Omarchy's sphere of control is roughly:

- the `omarchy-*` commands
- the Quickshell shell and its plugins
- the Hyprland and terminal configuration it ships
- its themes
- its install and migration scripts
- how it packages and configures what it installs

A crash in a program Omarchy merely installs is **not** an Omarchy bug unless
Omarchy's own packaging or configuration is implicated.

If it is not Omarchy's, say so and stop. Suggesting the right upstream project is
useful; filing there yourself is not part of this.

## Three conditions, all required

1. **It is a verified bug in Omarchy's sphere**, established on evidence. Issues
   are for verified bugs only. An "is this even a bug?" belongs on the Discord at
   <https://omarchy.org/discord>; a feature idea belongs in GitHub Discussions
   under Suggestions.
2. **The user has explicitly agreed.** Show them the exact title and body you
   propose, and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is missing
   or unauthenticated, do not install or authenticate it. Say so, and hand the
   user the finished text to submit themselves.

## Search before filing

A duplicate issue costs a maintainer more time than no report at all.

```bash
gh search issues --repo omacom/omarchy "<program> crash"
gh issue list --repo omacom/omarchy --state all --search "<signal> <program>"
```

Search on the crashing program, the signal, and distinctive symbols from the
backtrace — not on the wording of the title you were about to write.

`gh search issues` accepts only `open` or `closed` for `--state`, and errors on
anything else. Leaving it off searches both, which is what you want here.

Include **closed** issues. A matching issue closed as fixed, when the crash still
reproduces on a current system, is a regression — and reporting that is worth far
more than another duplicate.

## Adding to an existing report

If a plausible match comes back, read it properly first:

```bash
gh issue view <number> --repo omacom/omarchy --comments
```

Confirm it is genuinely the same failure. The same program crashing is not the
same bug if the trigger or the stack differs.

If it is the same, add to that issue rather than opening a new one — but only
when you have something the thread does not already contain: a different
reproduction, a symbolized stack where it has none, a narrower trigger, a version
where it regressed.

A comment that only says the bug happens to you too is noise. If that is all you
have, tell the user so and file nothing.

```bash
gh issue comment <number> --repo omacom/omarchy --body "..."
```

## Filing a new issue

Only when the search turns up nothing that matches:

```bash
gh issue create --repo omacom/omarchy --title "..." --body "..."
```

Include what happened, what was expected, steps to reproduce, system details from
`omarchy version`, and diagnostics from `omarchy debug --no-sudo --print` (which
also writes `/tmp/omarchy-debug.log`; the interactive `omarchy debug` can upload
it and print a shareable URL worth including).

`gh` cannot attach media. If a screenshot would help, save one and give the user
the path to drag into the web form.

## Signing

End the issue or comment with a line naming the model and agent harness that
produced it, so a human reader knows it was machine-authored:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so
plainly rather than inventing a version string.
