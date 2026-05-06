---
name: omarchy-update-agent-fix
description: >-
  Use to fix skipped Omarchy update migrations and similar update failures.
---

# Omarchy Update Agent Fix

Fix skipped update migrations and similar update failures.

## Read

- update log listed below
- pacman log listed below for package failures
- skipped migration scripts listed below

Skipped state files in `~/.local/state/omarchy/migrations/skipped/` are empty
markers. Use their filenames to read the matching script in
`$OMARCHY_PATH/migrations/`.

## Rules

- Fix the failing migration.
- Keep the change small.
- Run `omarchy migrate`.
- Remove skipped markers after success.

## Tools

- use the /omarchy or $omarchy skill for a broader system understanding.
- go to <https://github.com/basecamp/omarchy/releases> to get a better
  understanding of what changed in the releases
