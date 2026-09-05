# Reporting a Crash Upstream to Omarchy

Read this when evidence suggests Omarchy may contribute to a crash, or when ownership remains unclear after diagnosis.

## Determine the responsible layer

Approach ownership neutrally. Omarchy combines its own commands and configuration with Arch Linux and third-party applications. A crash inside a third-party process may be an application bug, but it can also be triggered by the way Omarchy packages, configures, launches, or integrates that application. Follow the evidence rather than starting from either conclusion.

Omarchy's sphere of control is roughly:

- the `omarchy-*` commands
- the Quickshell shell and its plugins
- the Hyprland and terminal configuration it ships
- its themes
- its install and migration scripts
- how it packages and configures what it installs

A third-party frame in the backtrace does not settle ownership by itself. Check the command line, Omarchy-managed configuration, recent Omarchy updates or migrations, and whether the failure reproduces without the relevant Omarchy customization.

When the evidence places the defect outside Omarchy, explain that connection plainly and point the user to the appropriate upstream project. When ownership remains uncertain, say what evidence is missing and use the Discord for triage rather than forcing an attribution.

## Three conditions, all required

1. **Evidence ties the failure to behavior Omarchy controls.** GitHub issues are most actionable when the responsible Omarchy command, configuration, packaging, integration, installation, or migration behavior has been identified. If the cause or owner is still uncertain, continue triage on the Discord at <https://omarchy.org/discord>; a feature idea belongs in GitHub Discussions under Suggestions.
2. **The user has explicitly agreed.** Show them the exact title and body you
   propose, and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is missing
   or unauthenticated, do not install or authenticate it. Say so, and hand the
   user the finished text to submit themselves.

## Search before filing

Search first so maintainers can keep evidence for the same failure together.

```bash
gh search issues --repo basecamp/omarchy "<program> crash"
gh issue list --repo basecamp/omarchy --state all --search "<signal> <program>"
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
gh issue view <number> --repo basecamp/omarchy --comments
```

Confirm it is genuinely the same failure. The same program crashing is not the
same bug if the trigger or the stack differs.

If it is the same, add to that issue rather than opening a new one — but only
when you have something the thread does not already contain: a different
reproduction, a symbolized stack where it has none, a narrower trigger, a version
where it regressed.

A comment that only repeats that the bug also occurs does not add diagnostic evidence. If that is all you have, tell the user the existing issue already covers it and file nothing.

```bash
gh issue comment <number> --repo basecamp/omarchy --body "..."
```

## Filing a new issue

Only when the search turns up nothing that matches:

```bash
gh issue create --repo basecamp/omarchy --title "..." --body "..."
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
