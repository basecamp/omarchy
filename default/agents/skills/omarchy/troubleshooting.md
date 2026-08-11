# Troubleshooting and Recovery

Use this guide when installed-system behavior is broken, uncertain, or needs to
be restored. Diagnose before resetting user state.

## Diagnosis Loop

1. Record the expected behavior, actual behavior, and shortest known reproduction.
2. Reproduce once when doing so is safe, capturing the exact output or visible symptom.
3. Inspect the relevant user configuration, packaged default, command `--help`, and resolved `omarchy-*` source.
4. Gather diagnostics without an interactive privilege prompt:

   ```bash
   omarchy version
   omarchy debug --no-sudo --print
   ```

   The same diagnostic report is written to `/tmp/omarchy-debug.log`.

5. Form the narrowest explanation supported by the evidence and make the smallest user-owned repair.
6. Repeat the reproduction and the component-specific completion checks.

Diagnosis is complete when the failure is either reproduced and resolved, or
reduced to a specific unresolved blocker with the supporting command output,
configuration, and logs identified. A reset that merely hides the cause does
not complete diagnosis.

## Component Recovery

Discover available refresh targets with `omarchy refresh --help`. A component
refresh replaces its user configuration with packaged defaults and normally
creates a timestamped backup:

```bash
omarchy refresh <component>
omarchy refresh config <path-relative-to-~/.config>
```

Pass `omarchy refresh config` a plain relative path with no `..` component. The
command resolves that argument in its source and destination paths, so a parent
segment can replace state outside `~/.config`.

Obtain user confirmation immediately before refreshing. State the exact target
path, what customization will be replaced, and where the backup should appear.
Afterward, confirm the backup exists, apply the restored component, and repeat
the original reproduction.

Use `omarchy reinstall` only when narrower diagnosis and component recovery
cannot restore the installation. Before running it, obtain confirmation and
state which user configuration and system state it may replace.

Recovery is complete when the original failure no longer reproduces, the
restored component passes its validators, and the backup or reversal path has
been reported to the user.

## Preparing Escalation

When local recovery cannot resolve the issue, retain the diagnosis output and
follow [`reporting-issues.md`](reporting-issues.md). Its report checklist defines
the complete evidence set and routes the result to support, discussion, or a
verified bug report.
