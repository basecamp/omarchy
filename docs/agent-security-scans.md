# Agent security scans

Omarchy can ask the selected default coding agent to review untrusted software
before it is installed or updated. Enable **Setup › Security › Agent Security
Scans**, or run:

```bash
omarchy agent security scan on
```

A default agent must be selected. When both settings are active, scans cover:

- requested AUR installs and their transitive AUR dependencies
- AUR package updates
- third-party plugin installs
- explicit third-party plugin updates through `omarchy plugin update`

The normal full `omarchy update` does not begin updating third-party plugins.

## Decisions and overrides

The agent returns `safe`, `suspicious`, or `unsafe`. Only `safe` continues
automatically. A person at an interactive terminal may explicitly override a
negative or incomplete review. `--yes`, piped/non-interactive commands, and
unattended updates never override one; they hold that item and continue the
rest of a batch where possible.

The review agent runs in a transient service with the host filesystem read-only
except for its private report and temporary directory. Session-bus and desktop
runtime sockets are hidden from it. This contains accidental or
prompt-injected writes while still allowing source inspection. Package builds
and plugins execute with their normal privileges only after they are cleared,
so an agent review remains a safety aid rather than a guarantee.

## Token use and cache

Reviews are keyed by the exact source content and the review-skill content.
Unchanged content reuses its prior audit without another agent call. For a Git
checkout, the reviewer receives an immutable commit and starts from the diff
against its last safe ancestor; the first review or a rewritten history gets a
full review. AUR build output is excluded from that identity, while any tracked
recipe drift before or during review is rejected. Plugin worktrees are hashed
again before a verdict is accepted, so changed source cannot inherit a result.

Cached audits live under
`~/.cache/omarchy/agent-security-scans/` with user-only permissions. Changing
either shipped review skill automatically invalidates relevant cache entries.

## One-command exceptions

Plugin commands retain explicit controls:

```bash
omarchy plugin add <url> --verify-with-agent
omarchy plugin add <url> --no-verify-with-agent
omarchy plugin update [id] --verify-with-agent
omarchy plugin verify <folder-or-id>
```

`--skill <file>` supplies a review method for one plugin command and implies a
review unless `--no-verify-with-agent` is also present.
