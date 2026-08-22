# Backups

Reference for the backup feature: what writes what, where state lives, and which decisions belong to which component. The user-facing guide is [`manual/52-backups.md`](../manual/52-backups.md); the design and the reasoning behind the engine choice are in [`plans/backup.md`](../plans/backup.md).

## Shape

restic is the engine. Omarchy owns the schedule, the state file, the panel, and the wizard; restic owns chunking, encryption, deduplication, retention, and the repository format. Nothing in the panel or the CLI status path talks to restic — they read a JSON file that the runner maintains, so an open panel costs nothing and never touches the repository.

```
omarchy-backup.timer  →  omarchy-backup.service  →  omarchy-backup-run  →  restic
                                                          │
                                                          ↓
                                              ~/.local/state/omarchy/backup/status.json
                                                          │
                                     ┌────────────────────┴────────────────────┐
                             omarchy backup status                    omarchy.backup panel
```

## Files

| Path | Contents |
|---|---|
| `~/.local/share/omarchy/backup/env` | `RESTIC_REPOSITORY` and the destination's credentials, mode 600 |
| `~/.local/share/omarchy/backup/passphrase` | The repository passphrase, mode 600, passed as `RESTIC_PASSWORD_FILE` |
| `~/.config/omarchy/backup/settings` | Non-secret settings: destination label and kind, retention, maintenance host, battery floor |
| `~/.config/omarchy/backup/excludes` | User exclude patterns, `$HOME`-relative |
| `$OMARCHY_PATH/default/backup/excludes` | Shipped exclude patterns, `$HOME`-relative |
| `~/.local/state/omarchy/backup/status.json` | The state file every reader watches |
| `~/.local/state/omarchy/backup/excludes` | Effective exclude file, absolute paths, regenerated each run |
| `~/.local/state/omarchy/backup/pause` | An epoch second, or `manual` |
| `~/.local/state/omarchy/backup/lock` | `flock` target for the per-machine run lock |
| `~/.local/state/omarchy/backup/backup.log` | Human-readable run log, trimmed at 2000 lines |
| `~/.local/state/omarchy/backup/maintenance` | `<epoch> <read-data subset index>` |

Credentials deliberately live under `~/.local/share`, not `~/.config`: `~/.config/omarchy` is documented user-intent config that people version and that the dots workflow syncs, and a delete-capable credential must not travel that way. `omarchy-backup-env` is the one place that knows this layout; every other command sources it.

## status.json

Written by `omarchy-backup-run` through a temporary file and `mv`, so a reader never sees a partial document. All times are epoch seconds.

| Field | Meaning |
|---|---|
| `phase` | `unconfigured`, `idle`, `running`, `paused`, `error` |
| `run_id`, `pid`, `started_at`, `updated_at` | Current or last run identity |
| `progress` | `percent`, `bytes_done`, `bytes_total`, `files_done`, throttled to one write per 3s |
| `last_backup` | `time`, `snapshot`, `result` (`complete`/`partial`/`failed`), `error`, `unreadable[]` |
| `last_complete` | The last snapshot known to hold everything; what restores default to |
| `last_maintenance` | Tracked apart from backup health, so a failed prune is not a failed backup |
| `last_skip` | `time` and `reason` — skips are recorded distinctly from failures |
| `last_warning` | When the stale-backup notification last fired |
| `snapshots` | Up to 10 recent snapshots for this host: `id`, `time`, `hostname` |
| `destination` | Redacted label, kind (`s3`/`local`/`other`), and whether it counts as off-site |
| `repository` | `size_bytes` and `snapshot_count` |
| `pause` | `until` (0 when open-ended) and `reason` |

A `running` record whose pid is gone is rewritten as `failed` at the start of the next run: a crash or a reboot mid-backup would otherwise leave the panel showing an upload forever.

## The run

`omarchy-backup-run` is the timer's target and the only thing that writes `status.json`. In order: exit 127 if restic is absent; mark `unconfigured` and stop if there are no credentials; reconcile a stale run; skip if paused (clearing an expired pause on the way); take the per-machine `flock`; skip if discharging below `BACKUP_BATTERY_FLOOR`; skip if a local destination's filesystem UUID does not match; write the effective exclude file; run `restic backup --json --one-file-system`; record the result; refresh snapshots and repository size; run maintenance if due; warn if backups have gone stale.

Exit codes are treated as distinct outcomes rather than pass/fail: `3` is a real snapshot that is missing unreadable files and is recorded as `partial` without advancing `last_complete`, and `11` is lock contention with another machine, which is a skip rather than a failure. Every skip is logged as a skip.

Pause is state, not a unit condition. A `ConditionPathExists` on the pause file would keep the unit from ever running while paused — including the run that would have noticed the pause had expired.

## Maintenance and multi-machine

`forget --prune` and `check` run monthly, not weekly: prune rewrites and re-uploads packs, which is bandwidth and API spend. `check` is paired with a rotating `--read-data-subset=<n>/12` so the whole repository is eventually read, since a plain `check` verifies structure and not content.

Only one machine does this. The wizard records the first machine to set the repository up as `BACKUP_MAINTENANCE_HOST`, and other machines skip maintenance entirely — keeping the lock-contending, expensive half of the work in one place. Backups themselves run everywhere and pass `--retry-lock 5m`.

Retention defaults to `--keep-hourly 24 --keep-daily 7 --keep-weekly 5 --keep-monthly 12`, grouped by `host,paths`, and is overridable per machine in the settings file.

## Units

`default/systemd/user/omarchy-backup.{service,timer}` are symlinked into `~/.config/systemd/user/` by the wizard and enabled there, rather than being enabled for everyone: backups are opt-in, and nothing about them should exist on a machine that never ran the setup. The service is `ConditionPathExists=%h/.local/share/omarchy/backup/env`, so removing the credentials makes it inert without leaving a broken unit behind. The timer is `OnCalendar=hourly` with `RandomizedDelaySec=15m` and `Persistent=true`, which catches up after sleep or shutdown.

## Panel

`shell/plugins/panels/backup/` is a first-party bar widget. `Service.qml` watches `status.json` with a `FileView`, plus a second `FileView` on the containing directory — the runner replaces the file by rename, and a `FileView` loses a file that is replaced rather than modified. `Model.js` is pure JavaScript that both the panel and `test/shell.d/backup-model-test.sh` load, so the display logic is tested without a compositor. Actions shell out to the same CLI a person would use, with an optimistic pause flag so the button reacts before the state file catches up.
