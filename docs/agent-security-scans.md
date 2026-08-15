# Agent security scans

Omarchy can ask the selected default coding agent for a quick malware and
install-abuse check before untrusted software is installed or updated. Enable
**Setup › Security › Agent Security Scans**, or run:

```bash
omarchy agent security scan on
```

A default agent must be selected. When both settings are active, scans cover:

- requested AUR installs and their transitive AUR dependencies
- AUR package updates
- third-party plugin installs
- explicit third-party plugin updates through `omarchy plugin update`

The normal full `omarchy update` does not begin updating third-party plugins.

The review stays in the install or update command's terminal. It does not open
a separate agent window. Progress is shown there while the selected agent runs
non-interactively. Pi, Oh My Pi, OpenCode, Claude Code, Codex, Grok, Gemini,
GitHub Copilot, and Crush use their respective unattended modes.

## What the check covers

This is a focused pre-install malware check, not a full vulnerability, code
quality, licensing, or upstream application audit. It looks for concrete signs
of credential theft, exfiltration, persistence, destructive behavior,
unexpected privilege, deception, and supply-chain abuse.

For AUR packages it reviews the packaging repository, provenance, integrity
checks, and install behavior. It does not download or decompile every vendor
payload. A missing payload inspection is a caveat, not automatically a reason
to block an otherwise ordinary pinned package. For plugins it prioritizes the
manifest, QML, scripts, commands, filesystem access, and network behavior over
ordinary documentation and media.

## Decisions and overrides

The agent returns `safe`, `suspicious`, or `unsafe`. Only `safe` continues
automatically. A person at an interactive terminal may explicitly override a
negative or incomplete review. `--yes`, piped/non-interactive commands, and
unattended updates never override one; they hold that item and continue the
rest of a batch where possible.

The review agent runs headlessly in a transient service with the host filesystem
read-only except for private report, cache, state, and temporary directories.
Session-bus and desktop runtime sockets are hidden from it. This contains
accidental or prompt-injected writes while still allowing source inspection.
Package builds and plugins execute with their normal privileges only after they
are cleared, so an agent review remains a safety aid rather than a guarantee.

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

Fresh reviews are prompted to finish in about 90 seconds and have a five-minute
hard limit. Compact progress updates are requested every 15 seconds during a
long step. Exact-content cache hits do not use agent tokens.

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
