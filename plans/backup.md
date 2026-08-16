# Plan: Backup — off-site, incremental, encrypted, panel-controlled

Revision 1.

## Problem

Omarchy has no answer for "my disk died", "my laptop was stolen", or "I deleted a folder I needed last month":

- Snapper snapshots cover the root filesystem only, live on the same disk, and `manual/47-system-snapshots.md` says outright they don't recover personal files.
- The dots plan (`plans/dots.md`) is config history + sync, and is explicit that it is *not* a backup — the local repo dies with the disk.
- The manual's file-safety story is "install Dropbox", which is sync, not backup: deletions and ransomware propagate instantly, and it only covers the folders you move into it.
- Mandatory full-disk encryption protects a lost laptop's *confidentiality*. Nothing protects your data's *existence*.

The ask: paste S3-compatible credentials, and Omarchy handles incremental, versioned, off-site backup from then on. Status, pause, and back-up-now live in a shell panel. Zero ongoing hassle.

## Engine choice: restic

- **Speaks S3-compatible natively** — AWS, Cloudflare R2, Backblaze B2, Hetzner Object Storage, MinIO, Wasabi — plus SFTP, rest-server, and plain local/USB paths through the same repository URL scheme. One integration, every destination.
- **Incremental without chains.** Content-defined chunking means each run uploads only new data, yet every snapshot is a complete, independently restorable image. No full-vs-incremental chain to replay (duplicity's disease), no periodic re-upload.
- **Versioning is the native model.** Snapshot per run; `forget --keep-hourly/daily/weekly/monthly` retention; `prune` reclaims space.
- **Client-side encryption always on.** The bucket provider stores ciphertext; keys never leave the machine.
- **Multi-machine works out of the box.** Snapshots are tagged with hostname; repository locks serialize maintenance. Two machines can share one bucket with zero coordination.
- Single static Go binary in Arch extra, battle-tested for a decade, `--json` output on every command the panel needs.

### Rejected engines

- **rsync** (from the prompt's "rsync or similar"): no S3 backend, no encryption, no real versioning without `--link-dest` server gymnastics, and it needs a shell on the far end. It's a transport, not a backup system.
- **rclone sync**: mirrors deletions and ransomware to the destination; "versioning" is provider-side or `--backup-dir` hacks; encryption is an extra layer (`rclone crypt`) you must not misconfigure.
- **borg/borgmatic**: excellent engine, but no S3 backend — needs borg installed on an SSH server, which kills the "paste bucket credentials" UX.
- **kopia**: credible restic rival, but ships its own server/UI/scheduler that duplicates the panel and timer we're building anyway, and has far less mindshare. restic is the smaller, better-known dependency.
- **duplicity**: incremental chains make restores slow and fragile.
- **Cloud sync clients** (Dropbox, already offered via Install > Service): sync is a different product. Backup must keep what you deleted.

## What gets backed up

`$HOME`, minus a shipped exclude file. Not the system: the OS is reproducible from the installer plus dots; `/home` is the irreplaceable part.

- Shipped excludes (`$OMARCHY_PATH/default/backup/excludes`): `~/.cache`, `~/.local/share/Trash`, browser cache dirs, package-manager caches, `node_modules`, thumbnail caches, mounted network shares. Regenerable bytes only — when in doubt, include.
- The dots repo (`~/.local/share/omarchy/dots.git`) is deliberately *included*: backup is what finally puts the config history off-site.
- Users extend via `~/.config/omarchy/backup/excludes` (one pattern per line, restic syntax). No include-list to curate — that's the hassle we're avoiding.
- The first-run summary shows the measured size before uploading, so a home directory full of VM images isn't a surprise on a metered plan.

## Setup: `omarchy-setup-backup`

A gum wizard in the terminal, in the mold of `omarchy-setup-security-sshd` (flags for every prompt so it can run unattended), launched from a new _Setup > Backup_ menu entry via `omarchy-launch-floating-terminal-with-presentation`:

1. **Destination.** Choose: S3-compatible bucket (prompts for endpoint URL, bucket name, access key ID, secret key) / any restic repository URL (expert escape hatch) / local path (USB or NAS mount — free courtesy of restic).
2. **Install + verify.** `omarchy-pkg-add restic`, then probe the repository: if the bucket is empty, `restic init`; if a repository already exists (second machine, or re-setup), ask for its passphrase instead of generating one, and offer the restore path (below).
3. **Encryption passphrase.** Generate a strong passphrase, display it once, and require typed confirmation that it's been saved somewhere off this machine (password manager, paper). Plain warning: lose the passphrase and the backups are unreadable — Omarchy cannot recover it.
4. **First backup runs immediately** in the terminal with live progress, so the user watches it work once. On success: timer enabled, bar widget placed (`enablePlugin` IPC).

Teardown is `omarchy-setup-backup --remove`: disable timer, remove widget, delete local credentials — after stating clearly that the repository and its snapshots stay untouched in the bucket.

Credential storage: `~/.config/omarchy/backup/` (0700) holding `env` (`RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) and `passphrase` (0600, referenced via `RESTIC_PASSWORD_FILE`). Plain mode-restricted files are the deliberate choice and the house pattern (agents API keys live in `~/.config/omarchy/agents/`; the gnome-keyring is configured *passwordless* by `install/user/default-keyring.sh`, so `secret-tool` would add a new precedent while buying nothing). Full-disk encryption is mandatory on Omarchy; the passphrase's job is to blind the storage provider, not to survive a compromised user account. A keyring would also break the headless timer — locked keyring at 3am means no backups.

## Automatic runs: systemd user timer

The repo's first `.timer`. `default/systemd/user/omarchy-backup.timer` + `omarchy-backup.service`, shipped to `/usr/lib/systemd/user/` via the `omarchy-settings` PKGBUILD (the `install -Dm644` line must be added there, per `docs/file-layout.md`). Enabled by the setup wizard, not `enable-user-units.sh` — backup is opt-in, so it follows the `omarchy-install-service-tailscale` enable/disable pattern:

- Timer: hourly `OnUnitActiveSec` with randomized delay, `Persistent=true` so a laptop that slept through a slot catches up on wake, `WantedBy=timers.target`.
- Service: oneshot running `omarchy-backup-run`, with `ConditionPathExists=%h/.config/omarchy/backup/env` (unconfigured = inert) and `ConditionPathExists=!%h/.local/state/omarchy/toggles/backup-paused` (the pause flag gates the unit itself, the `omarchy-crash-watch` idiom).
- `omarchy-backup-run` guards before touching the network: paused → skip; on battery and low (existing `omarchy-battery-*` helpers) → skip; a run already active (lock file, the `omarchy-update.lock` idiom) → skip. Skips are logged as skips, not errors. Missing restic exits 127, the `omarchy-snapshot` convention for "tool not installed".
- Pipeline per run: `restic backup --json` (streamed, see state below), then — on a weekly cadence, not every run — `restic forget --prune` per retention policy and a cheap `restic check`. Retention defaults: `--keep-hourly 24 --keep-daily 7 --keep-weekly 5 --keep-monthly 12`, overridable in a `settings` file the wizard writes.
- Failure policy: a single failed run is silent (flaky café wifi must not nag). No successful backup for 24 hours → one `omarchy-notification-send` warning. The panel always shows the exact state and last error.

## Status plumbing: one state file

`omarchy-backup-run` maintains `~/.local/state/omarchy/backup/status.json`: phase (`idle` / `running` / `paused` / `error` / `unconfigured`), progress percent and bytes during a run, last snapshot time and id, snapshot count, repository size, last error text, pause-until timestamp. Written atomically on every phase change, throttled during upload.

This is the agents-plugin pattern (`shell/plugins/agents/`): the background job writes JSON records, the panel is strictly a display watching them with `FileView { watchChanges: true }` (watching the parent directory until the file first exists). The CLI (`omarchy backup status`) reads the same file; nobody shells out to restic for status, so the panel stays instant and the repository is only touched by real runs.

## Panel: `omarchy.backup` bar widget

A first-party plugin at `shell/plugins/panels/backup/`, modeled on the dropbox panel — the closest existing analog (background daemon with pause/resume, status, quota): `manifest.json` (kinds `["bar-widget"]`), `Panel.qml` extending `Ui/Panel.qml`, `Service.qml` for state, `Model.js` for parsing, built from the shared `PanelHero` / `PanelSectionHeader` / `PanelActionButton` kit with `Color`/`Style` theme tokens.

- **Bar icon states**: unobtrusive when healthy, progress animation while a run uploads, dimmed when paused, attention color when the last run failed or no backup has succeeded in over a day.
- **Panel**: hero line ("Backed up 12 minutes ago to Backblaze"), repo size and snapshot count, live progress bar during a run, recent snapshots list, and actions: **Back Up Now**, **Pause** (1 hour / until tomorrow / until resumed) / **Resume**, and a link into the restore workflow (opens a terminal — restores confirm and print, which wants a terminal, same rationale as the plugin Add/Remove flows).
- Actions call `omarchy backup now|pause|resume` detached, with the dropbox panel's optimistic-state trick (`_desired` overrides reality until the state file catches up) so buttons react instantly.
- IPC target `omarchy.backup` (`manageIpc: false`, custom verbs `refresh` / `run` / `status` on top of the inherited open/close/toggle), reachable as `omarchy-shell omarchy.backup toggle`.
- The widget is placed automatically when setup succeeds, not shipped in the default bar — no dead icon for people who never set backup up.

## Restore

`GROUP_DESCRIPTIONS[backup]` added in `bin/omarchy`; the router derives verbs from filenames, so these are just `bin/omarchy-backup-*` executables with `# omarchy:summary=` metadata:

- `status` (`--json` for scripts), `now`, `pause [duration]`, `resume`, `log`, `snapshots`
- `restore <path> [--at <time|snapshot>]` — restores next to the original as `<name>.restored` by default; `--overwrite` restores in place after a confirm. Accepts a directory to recover a whole tree.
- `browse` — `restic mount` on a runtime-dir FUSE mount + opens the file manager: every snapshot browsable as dated folders. This is the "super easy" restore story — no flags to learn, just copy files out.
- **Disaster recovery**: on a fresh machine, `omarchy-setup-backup` pointed at the existing bucket asks for the passphrase, detects prior hosts in the repository, and offers "restore home folder from <host>'s latest snapshot" before the timer even starts. This is the payoff of the whole feature and belongs in v1.

## Versioning and conflicts

Explicitly part of the design, and deliberately boring:

- **Versioning** is restic's snapshot model plus the retention policy. Nothing is ever overwritten server-side; a version disappears only when retention forgets it.
- **Conflicts cannot happen** because backup is one-way and append-only. Machines never merge state: each run adds a snapshot tagged with its hostname, restic's repository locks serialize concurrent maintenance, and restores default to your own host's snapshots. Two-way file sync is a different product (Dropbox for files, dots for configs); this feature refuses to become one — that refusal *is* the conflict story.
- **Honest limit**: credentials on the machine can delete the bucket, so ransomware running as the user could destroy the backups it's supposed to protect against. v1 documents the mitigation (bucket-side object lock / versioning, or a second restricted key) in the manual; an append-only mode is an open question below.

## Rollout

- Fully opt-in: nothing installed, no timer, no widget until _Setup > Backup_ runs.
- No migration needed for existing users.
- Docs per the documentation layout: a new `manual/49-backups.md` (user guide: setup, restore, browse, the passphrase warning, multi-machine), `docs/backup.md` (reference: state file schema, unit wiring, retention), and `manual/47-system-snapshots.md` / `24-commercial-apps-services.md` cross-links so "snapshots vs backup vs sync" is stated in one place.
- Tests: restic's local backend makes the whole engine testable hermetically — no S3 in CI. Cover: CLI metadata (`omarchy commands --check` via `test/cli` fails without summaries); state-file transitions (running → idle, error paths); pause flag honored by both the unit condition and `omarchy-backup-run`; excludes actually applied; retention args; restore round-trip (backup a fixture tree to a local repo, restore, diff); setup wizard's unattended flag path; menu acceptance test for the new entry.

## Open questions

1. Default excludes: do multi-GB regenerables like VM disks and local LLM models stay in (include-by-default purity) or out (metered-connection mercy)? The first-run size preview softens either answer.
2. Cadence and retention defaults: hourly may be too chatty for metered/mobile connections — detect metered via NetworkManager and skip, or make cadence a wizard question?
3. Append-only protection: rest-server has `--append-only`, S3 needs provider object-lock. Worth a guided option in the wizard, or documentation only?
4. Bandwidth limiting (`--limit-upload`): expose in settings, in the wizard, or not at all in v1?
5. Should the bar widget exist for unconfigured users as a discoverable "Backups: not set up" nudge, or is the menu entry enough? (Leaning: menu only; the bar is not for ads.)
6. Naming: plain `omarchy backup` vs a branded name in the dots tradition. Plain reads better in a disaster ("omarchy backup restore") — leaning plain.
7. Timed pause ("until tomorrow") needs more than a touch file: store the resume timestamp in the flag and have the next timer firing clear an expired pause, or lean on `systemctl --user` transient timers?
