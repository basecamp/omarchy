# Plan: Backup — off-site, incremental, encrypted, panel-controlled

Revision 2. Rev 2 incorporates adversarial review by codex (xhigh): honest threat model, secrets moved out of the backup scope and out of `~/.config`, corrected timer/pause mechanics, reordered setup, and corrected restic claims (exclude expansion, exit codes, partial backups, lock contention, prune cost, fuse2).

## Problem

Omarchy has no answer for "my disk died", "my laptop was stolen", or "I deleted a folder I needed last month":

- Snapper snapshots cover the root filesystem only, live on the same disk, and `manual/47-system-snapshots.md` says outright they don't recover personal files.
- The dots plan (`plans/dots.md`) is config history + sync, and is explicit that it is *not* a backup — the local repo dies with the disk.
- The manual's file-safety story is "install Dropbox", which is sync with bounded retention, not backup: it only covers folders you move into it, deleted-file recovery is time-limited, and your data's survival is tied to one account at one vendor.
- Full-disk encryption (the install default) protects a lost laptop's *confidentiality*. Nothing protects your data's *existence*.

The ask: paste S3-compatible credentials, and Omarchy handles incremental, versioned, off-site backup from then on. Status, pause, and back-up-now live in a shell panel. Zero ongoing hassle.

## Threat model

Stated up front so the feature never overpromises:

- **Defends against**: disk death, machine loss/theft, accidental deletion or overwrite discovered later, a botched migration — anything where you still control your storage account and passphrase.
- **Does not defend against (v1)**: an attacker or malware running as your user on the live machine. The machine necessarily holds credentials that can write to — and, for retention, delete from — the repository, so ransomware with user privileges can attack the backups too. Provider-side object versioning/immutability can mitigate this but is a per-provider, tested procedure (delete markers, prune's space-reclamation assumptions), not a checkbox; the manual documents it honestly. True split-authority (backup-only key on the machine, maintenance from elsewhere) is the v2 path, sketched in open questions.
- **App-consistency limits**: files are read live. Running databases, VM disks, and containers may snapshot in a crash-consistent state at best. The manual says so.
- **Scope boundary**: personal files under `$HOME` for the invoking user. Not `/etc`, not `/var`, not other users, not system package state — the OS is reinstallable from the ISO, and configs are the dots plan's job.

## Engine choice: restic

- **Speaks S3-compatible natively** — AWS, Cloudflare R2, Backblaze B2, Hetzner Object Storage, MinIO, Wasabi — plus SFTP, rest-server, and plain local/USB paths through the same repository URL scheme. One integration, every destination.
- **Incremental without chains.** Content-defined chunking means each run uploads only new data, and snapshots have no predecessor chain to replay (duplicity's disease). Snapshots do share deduplicated blobs — integrity of shared data matters, which is why periodic verification is part of the design below.
- **Versioning is the native model.** Snapshot per run; `forget --keep-*` retention; `prune` reclaims space.
- **Client-side encryption always on.** The bucket provider stores ciphertext; keys never leave the machine.
- **Multi-machine capable.** Snapshots record hostname; retention groups by host/path; repository locks coordinate concurrent access (with retry handling — see multi-machine section).
- Packaged in Arch extra (`restic`, plus `fuse2` as the optional dependency `mount` needs), battle-tested for a decade, machine-readable `--json` output on the specific commands we script: `backup`, `snapshots`, `stats`, `forget`, `restore`, `version` — enumerated because not every restic command supports JSON.

### Rejected engines

- **rsync** (from the prompt's "rsync or similar"): no S3 backend, no encryption, no real versioning without `--link-dest` server gymnastics, and it needs a shell on the far end. It's a transport, not a backup system.
- **rclone sync**: mirrors deletions and ransomware to the destination; "versioning" is provider-side or `--backup-dir` hacks; encryption is an extra layer (`rclone crypt`) you must not misconfigure.
- **borg/borgmatic**: excellent engine, but no S3 backend — needs borg installed on an SSH server, which kills the "paste bucket credentials" UX.
- **kopia**: credible restic rival, but ships its own server/UI/scheduler that duplicates the panel and timer we're building anyway, and has far less mindshare. restic is the smaller, better-known dependency.
- **duplicity**: incremental chains make restores slow and fragile.
- **Cloud sync clients** (Dropbox, already offered via Install > Service): sync is a different product with different guarantees; backup must keep what you deleted, on your terms, for as long as your retention policy says.

## What gets backed up

`$HOME`, minus excludes, with `--one-file-system` so mounted NAS shares, removable disks, and FUSE mounts are never traversed by a static pattern list's grace.

- **Built-in excludes, not user-editable**: the backup's own secrets directory (`~/.local/share/omarchy/backup/` — the repository must never contain the credentials that unlock it), restic's cache (`~/.cache/restic`), `~/.cache`, `~/.local/share/Trash`.
- **Shipped default excludes** (`$OMARCHY_PATH/default/backup/excludes` as `$HOME`-relative patterns, expanded to absolute paths when the setup wizard writes the effective exclude file — restic does not expand `~` in patterns): browser caches, package-manager caches, `node_modules`, thumbnail caches. Regenerable bytes only — when in doubt, include.
- The dots repo (`~/.local/share/omarchy/dots.git`) is deliberately *included*: backup is what finally puts the config history off-site.
- Users extend via `~/.config/omarchy/backup/excludes` (one pattern per line, restic syntax, expanded the same way). No include-list to curate — that's the hassle we're avoiding.
- The first-run summary shows the measured *source* size before uploading — labeled as such, cancellable, and explicitly not an upload estimate (dedup and compression usually shrink it dramatically).

## Setup: `omarchy-setup-backup`

A gum wizard in the terminal, in the mold of `omarchy-setup-security-sshd` (flags for every prompt so it can run unattended), launched from a new _Setup > Backup_ menu entry via `omarchy-launch-floating-terminal-with-presentation`. Every step is idempotent and the wizard records its phase, so a closed terminal or dropped connection resumes cleanly on re-run instead of leaving orphaned credentials or a half-initialized repository. Nothing is enabled until the first backup succeeds.

1. **Destination.** Choose: S3-compatible bucket — prompts for endpoint URL, bucket (with optional prefix), region (optional, defaulted), access key ID, secret key / any restic repository URL plus extra env vars (expert escape hatch — covers session tokens, custom CAs, path-style quirks) / local path (USB or NAS mount; recorded with its filesystem identity, see below). Unencrypted-disk installs get a plain warning here that the credentials will sit on an unencrypted drive.
2. **Passphrase first.** Generate a strong passphrase (or accept an existing repository's), *then* probe: `restic cat config` distinguishes repository-absent (exit 10 → `restic init`), wrong passphrase (exit 12 → re-prompt), auth/network failures (→ fix credentials, nothing created). Never infer "safe to init" from an apparently empty bucket.
3. **Recovery card.** The wizard writes and displays a recovery record — endpoint, bucket, prefix, repository ID, restore instructions, a blank line for the passphrase — and requires typed confirmation that passphrase and card are saved off this machine. Plain warning: lose the passphrase and the backups are unreadable; Omarchy cannot recover it. The card contains no live credentials.
4. **First backup runs immediately** in the terminal with live progress, so the user watches it work once. On success: timer enabled, bar widget placed (`enablePlugin` IPC). On an existing repository (second machine or reinstall), the wizard detects prior hosts and offers the disaster-recovery restore (below) before any timer starts.

Teardown is `omarchy-setup-backup --remove`: stop and wait for any running backup, unmount any browse session, disable the timer, remove the widget, delete local credentials and state — then state clearly that the repository and its snapshots remain untouched in the bucket, and that restic stays installed.

**Secrets layout**: `~/.local/share/omarchy/backup/` (0700) holds `env` (`RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, extras) and `passphrase` (0600, via `RESTIC_PASSWORD_FILE`); secrets pass to restic only via environment and files, never argv. Non-secret settings (destination label, retention, cadence) live separately in `~/.config/omarchy/backup/` — `~/.config/omarchy` is documented user-intent config that people version and that dots will sync, so live delete-capable credentials must not live there. Mode-restricted plain files are still the deliberate choice over the keyring: Omarchy's default keyring is configured passwordless by `install/user/default-keyring.sh` (so `secret-tool` adds a precedent while buying nothing), and a locked keyring at 3am would mean no backups. Full-disk encryption — the default, though not universal — covers the at-rest story; the threat model section covers the rest honestly.

## Automatic runs: systemd user timer

The repo's first `.timer`. `default/systemd/user/omarchy-backup.timer` + `omarchy-backup.service`, shipped disabled to `/usr/lib/systemd/user/` via the `omarchy-settings` PKGBUILD in the omarchy-pkgs repo (with the matching `package_defaults` fixture update in `test/shell.d/config-test.sh`). Enabled by the setup wizard, not `enable-user-units.sh` — backup is opt-in, following the `omarchy-install-service-tailscale` enable/disable pattern.

- Timer: `OnCalendar=hourly` with `RandomizedDelaySec`, `Persistent=true` — which only works with calendar timers, and gives catch-up-at-login after sleep or shutdown. User timers run only while a session exists; that's fine — backups happen while you use the machine, and `Persistent=` covers the gap. No lingering required.
- Service: oneshot running `omarchy-backup-run`, with `ConditionPathExists=%h/.local/share/omarchy/backup/env` (unconfigured = inert). **Pause is not a unit condition**: a condition-gated unit never executes while paused and so could never notice a pause expiring. Instead the runner always starts, reads the pause record (a resume-at timestamp or `manual` sentinel in the state directory), clears it if expired, and exits as a logged skip if still active.
- Further guards before touching the network: discharging with battery below 20% (a new quiet predicate command — `omarchy-battery-low` is a notifier, not a check) → skip; a run already active (per-machine lock file; restic's repository locks handle cross-machine, below) → skip. Skips are logged as skips and recorded distinctly from failures. Missing restic exits 127, the `omarchy-snapshot` convention for "tool not installed".
- Backup: `restic backup --json` streamed into the state file. Exit 3 (some files unreadable) produces a *partial* snapshot: recorded as `partial`, surfaced in the panel with the unreadable paths, and never advances the last-complete-success marker that restore defaults to.
- Maintenance, tracked separately from backup health: `forget --prune` monthly, not weekly — prune can download and re-upload packs, so it's real bandwidth and API spend. `check` monthly plus a rotating `check --read-data-subset` slice so all data gets read over time — plain `check` alone verifies structure, not content. Retention defaults: `--keep-hourly 24 --keep-daily 7 --keep-weekly 5 --keep-monthly 12`, overridable in settings.
- Notification policy: a single failed run is silent (flaky café wifi must not nag). No successful backup for 24 hours → one `omarchy-notification-send` warning, repeated weekly while the condition persists — one-warning-forever would let a dead credential rot silently for months. The panel always shows the exact state and last error.
- Local-path destinations: setup records the target filesystem's identity (UUID), and every run verifies it before writing — an absent USB disk must produce a skip, not a backup quietly written into an empty mountpoint directory on the root filesystem. Local destinations are labeled non-off-site in the panel.

## Status plumbing: one state file

`omarchy-backup-run` maintains `~/.local/state/omarchy/backup/status.json`, written atomically (rename) on every phase change and throttled during upload:

- `phase` (`idle` / `running` / `paused` / `error` / `unconfigured`), `run_id`, `pid`, `started_at`, `updated_at`, progress percent and bytes during a run
- `last_backup` { time, snapshot id, result `complete` / `partial` / `failed`, error text, unreadable paths }
- `last_maintenance` { time, result, error } — separate, so a prune failure doesn't masquerade as a backup failure
- `snapshots` (recent list for the panel), `destination` (redacted label — provider/bucket, never credentials), repository size, snapshot count, `pause` { until, reason }
- Stale-run reconciliation: on every start, the runner checks a `running` record's pid; a dead pid (crash, reboot mid-backup) is rewritten as `failed` so the panel can never show a phantom eternal run.

This is the agents-plugin pattern (`shell/plugins/agents/`): the background job writes JSON, the panel is strictly a display watching it with `FileView { watchChanges: true }` — keeping the parent-directory watcher permanently and re-binding after the atomic rename, since `FileView` loses files that are replaced rather than modified. The CLI (`omarchy backup status`) reads the same file; nobody shells out to restic for status, so the panel stays instant and the repository is only touched by real runs.

## Panel: `omarchy.backup` bar widget

A first-party plugin at `shell/plugins/panels/backup/`, modeled on the dropbox panel — the closest existing analog (background daemon with pause/resume, status, quota): `manifest.json` (kinds `["bar-widget"]`), `Panel.qml` extending `Ui/Panel.qml`, `Service.qml` for state, `Model.js` for parsing, built from the shared `PanelHero` / `PanelSectionHeader` / `PanelActionButton` kit with `Color`/`Style` theme tokens.

- **Bar icon states**: unobtrusive when healthy, progress animation while a run uploads, dimmed when paused, attention color when the last run failed, was partial, or no complete backup has succeeded in over a day.
- **Panel**: hero line ("Backed up 12 minutes ago to Backblaze"), repo size and snapshot count, live progress bar during a run, recent snapshots list, and actions: **Back Up Now**, **Pause** (1 hour / until tomorrow / until resumed) / **Resume**, and a link into the restore workflow (opens a terminal — restores confirm and print, which wants a terminal, same rationale as the plugin Add/Remove flows).
- Actions call `omarchy backup now|pause|resume` detached, with the dropbox panel's optimistic-state trick (`_desired` overrides reality until the state file catches up) so buttons react instantly.
- IPC target `omarchy.backup` (`manageIpc: false`, custom verbs `refresh` / `run` / `status` on top of the inherited open/close/toggle), reachable as `omarchy-shell omarchy.backup toggle`.
- The widget is placed automatically when setup succeeds, not shipped in the default bar — no dead icon for people who never set backup up.

## Restore

`GROUP_DESCRIPTIONS[backup]` added in `bin/omarchy`; the router derives verbs from filenames, so these are just `bin/omarchy-backup-*` executables with `# omarchy:summary=` metadata:

- `status` (`--json` for scripts), `now`, `pause [duration]`, `resume`, `log`, `snapshots`
- `restore <path> [--at <time|snapshot>]` — restores into a staging directory (`~/Restored/<timestamp>/`, preserving relative layout) by default; `--in-place` overwrites after a confirm and after snapshotting the current version first, so an interrupted in-place restore is itself recoverable. Paths are passed to restic as literal include arguments, never shell-interpreted. Defaults to the last *complete* snapshot, never a partial one. Accepts a directory to recover a whole tree.
- `browse` — `restic mount` (which needs `fuse2`, installed by setup alongside restic) run as a foreground process in a terminal on a runtime-dir mountpoint, with the file manager opened on it; unmount on exit, with stale-mount cleanup at the start of every run and at teardown. Every snapshot browsable as dated folders — the "super easy" restore story: no flags to learn, just copy files out.
- **Disaster recovery**: on a fresh machine, `omarchy-setup-backup` pointed at the existing bucket asks for the passphrase, lists prior hosts, and offers "restore home folder from <host>'s latest complete snapshot" into the new home before the timer starts — mapping the snapshot's old home path onto the new one (restic restores the recorded hierarchy; the wizard handles the `snapshot:subfolder` mapping and warns when the username differs). This is the payoff of the whole feature and belongs in v1.

## Versioning, conflicts, and multi-machine

Explicitly part of the design, and deliberately boring:

- **Versioning** is restic's snapshot model plus the retention policy. Nothing is overwritten server-side; a version disappears only when retention forgets it.
- **Conflicts cannot happen** because backup is one-way and append-only in its semantics. Machines never merge state: each run adds a snapshot recording its hostname, retention groups by host, and restores default to your own host's snapshots. Two-way file sync is a different product (Dropbox for files, dots for configs); this feature refuses to become one — that refusal *is* the conflict story.
- **Coordination is real, though**: restic's repository locks default to zero retries, so runs use `--retry-lock` and treat lock contention (exit 11) as a retryable skip, not a failure. Exactly one machine — the first one set up, recorded in the repository — runs prune and check; the others only back up, which keeps the expensive, contention-prone maintenance in one place. Hostname is the retention grouping key, so the manual notes that cloned machines need distinct hostnames.
- **Shared-repository trade-off, stated honestly**: all passphrases on a shared repository unlock the same master key, so compromising one machine exposes every machine's data in it, and removing a password later doesn't un-ring that bell. The default stays one shared repository — it's what makes cross-host disaster recovery a first-run feature — with per-machine repositories documented for people who want isolation over convenience.

## Rollout

- Fully opt-in: no packages installed, no units enabled, no scheduled work, no widget until _Setup > Backup_ runs (the unit files themselves ship disabled with `omarchy-settings`, like every other default unit).
- No migration needed for existing users.
- Docs per the documentation layout: a new `manual/49-backups.md` (user guide: setup, restore, browse, the passphrase warning and recovery card, multi-machine, the threat model in plain words — including provider lifecycle policies: cold-storage/archival tiers silently break restic and must not be enabled on the bucket), `docs/backup.md` (reference: state file schema, unit wiring, retention, lock/maintenance topology), and `manual/47-system-snapshots.md` / `24-commercial-apps-services.md` cross-links so "snapshots vs backup vs sync" is stated in one place.
- Tests: restic's local backend covers the engine logic hermetically — CLI metadata (`omarchy commands --check` via `test/cli`), state-file transitions including stale-run reconciliation and partial results, pause expiry, exclude expansion (tilde-free, absolute), retention args, restore round-trip into staging (fixture tree → local repo → restore → diff), wizard's unattended flag path and resume-after-abort, menu acceptance. S3 specifics (endpoint styles, auth failures, prefixes) get an integration pass against MinIO in the acceptance VM. The widget and panel go through `agents/skills/visual-verification.md` in the running UI: unconfigured, first backup, running, partial, failure, stale, paused, browse-mounted, long labels, teardown.

## Open questions

1. Default excludes: do multi-GB regenerables like VM disks and local LLM models stay in (include-by-default purity) or out (metered-connection mercy)? The first-run size preview softens either answer.
2. Cadence: hourly may be too chatty for metered/mobile connections — detect metered via NetworkManager and skip, or make cadence a wizard question?
3. Split-authority hardening (v2 sketch): a backup-only credential on the machine (no delete permission), with prune run by the designated maintenance machine under a separate credential — or provider-side object versioning with a tested recovery runbook per provider. Which providers make this tractable enough to wizard?
4. Bandwidth limiting (`--limit-upload`): expose in settings, in the wizard, or not at all in v1?
5. Should the bar widget exist for unconfigured users as a discoverable "Backups: not set up" nudge, or is the menu entry enough? (Leaning: menu only; the bar is not for ads.)
6. Naming: plain `omarchy backup` vs a branded name in the dots tradition. Plain reads better in a disaster ("omarchy backup restore") — leaning plain.
7. Per-machine repositories as a wizard option (key isolation) vs documentation only, given the shared-repo default exists for cross-host restore.
