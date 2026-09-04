# Dropbox

Dropbox status, storage usage, login, **selective sync**, and recent synced
files in the Omarchy bar.

Installed and enabled by `omarchy-install-service-dropbox`, which also adds the
`dropbox`, `dropbox-cli`, and `nautilus-dropbox` packages.

| File | Role |
|---|---|
| `Panel.qml` | Bar button, popup layout, keyboard cursor |
| `Service.qml` | State and every `dropbox-cli` invocation |
| `Model.js` | Pure formatting/parsing helpers |
| `status.py` | Account, storage, and recent-files probe |
| `folders.py` | Folder tree + selective-sync state |
| `DropboxIcon.qml` | The glyph |

Both helpers print a single JSON object on stdout and never raise; the QML side
treats a non-zero exit or unparseable output as an error state.

## Selective sync

The **Synced folders** section lists the folders inside your Dropbox with a
switch each. Switching one off runs `dropbox-cli exclude add` (Dropbox deletes
the local copy but keeps the cloud copy); switching it back on runs
`dropbox-cli exclude remove` and the folder is downloaded again.

This replaces the selective-sync dialog that used to live behind the Dropbox
tray icon's right-click menu, which no longer exists now that the bar plugin has
taken the tray's place.

### Keys

| Key | Action |
|---|---|
| `j` / `k` / `↓` / `↑` | Move the cursor (header → folders → recent files) |
| `l` / `→` / `Enter` | Open the highlighted folder |
| `h` / `←` | Go up one folder |
| `s` | Sync or unsync the highlighted folder |
| `r` | Refresh status and folders |
| `p` | Pause or resume syncing |
| `Esc` | Close |

`Enter` only ever navigates. A folder with no subfolders is not browsable and
`Enter` does nothing on it, rather than falling back to a toggle that would
unsync whatever the cursor happened to be on. `s` and the switch own toggling.

### Settings

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `60` | Status poll interval |
| `showSyncedFolders` | `true` | Show the Synced folders section |
| `maxFolderRows` | `50` | Cap on folders listed per directory |

### Limitation: excluded folders are leaves

The Dropbox CLI has no remote directory listing. An excluded folder is deleted
locally, so its children cannot be enumerated and it is shown as a toggle-only
row with no `›`. Sync it back on and it becomes browsable once the download
lands. Folders that *are* synced can be browsed to any depth.

### Implementation notes

Two details of `dropbox-cli` that `folders.py` depends on:

1. `exclude list` prints each path through `relpath()`, so its output is
   relative to the process cwd. It is therefore invoked with `cwd="/"`, which
   makes every line root-relative and absolute with a single `/` prefix — no
   guessing at where the Dropbox folder is or what it is named.
2. `exclude add`/`remove` take absolute paths and block until the daemon
   accepts the change, so they always run through QML's async `Process`.

Folder names routinely contain spaces and other shell metacharacters, so
`exclude list` output is only ever stripped of whitespace, never split.

A folder's children are the union of the subdirectories present on disk and the
ignore-set entries parented there. A path can appear in both for a moment while
the daemon is deleting it; excluded wins, because that is the state the user
just asked for.

Toggles are optimistic — the switch flips immediately and `folders.py` is
re-polled a few times until reality agrees, the same trick `Service.qml` already
uses for pause/resume. Only an in-flight `exclude add`/`remove` (`syncBusy`)
blocks another toggle; a background folder listing (`foldersBusy`) does not, so
an undo right after a toggle is never swallowed.
