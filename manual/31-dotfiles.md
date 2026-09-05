# Dotfiles

Omarchy is primarily configured through the so-called dotfiles that live in `~/.config`. Those are considered your files for your changes. The files that live in `/usr/share/omarchy` belong to Omarchy itself, and you shouldn't be messing with those. If you need to change anything in `/usr/share/omarchy`, you should be overwriting the value in `~/.config` instead.

The key configs can be edited straight from the Omarchy menu (`Super + Space`), like _Setup > Monitors_, _Setup > Keybindings_, _Setup > Input_, and _Setup > Config > [file]_. When you do it this way, any process that needs restarting after config edits automatically will be after you quit the editor (Neovim by default — `:wq`, remember! — but you can change that via _Setup > Defaults > Editor_).

Here's a list of the key files in `~/.config` and what they control:

| File                  | Purpose              |
| ----------------------- | --------------------- |
| `~/.config/hypr/hyprland.lua` | The main Hyprland config. Loads the Omarchy defaults plus your override files below. [Learn more about Hyprland configs](https://wiki.hypr.land/Configuring/).  |
| `~/.config/hypr/bindings.lua` | Your own keybindings and overrides of the defaults. |
| `~/.config/hypr/monitors.lua` | Controls your monitors, resolution, and position. |
| `~/.config/hypr/input.lua` | Controls your keyboard layout, mouse, and trackpad settings. |
| `~/.config/hypr/looknfeel.lua` | Controls gaps, borders, animations, and the rest of the look. |
| `~/.config/hypr/autostart.lua` | Controls extra processes started with the session. |
| `~/.config/omarchy/shell.json` | Controls the Omarchy shell: bar position, layout, and widgets, plus screensaver, lock, and idle timings. |
| `~/.config/foot/foot.ini` | Controls your terminal (foot is the default). |
| `~/.XCompose` | Defines your quick-access emoji and name/email autocomplete. Make sure to run `omarchy-restart-xcompose` after making changes. |

If you end up making a lot of changes to tweak your own setup, it's a good idea to backup all these dotfiles. [Stow is a great way to do that](https://www.youtube.com/watch?v=NoFiYOqnC4o).

## Cloud backup

Omarchy can save your whole home directory — desktop settings, dotfiles, documents, projects, and application data — to any cloud provider supported by [rclone](https://rclone.org/): Google Drive, Dropbox, OneDrive, S3-compatible storage, WebDAV/Nextcloud, and many more. Run `omarchy backup setup` to configure a provider and a shared folder. That opens rclone's provider setup when needed, then records only the chosen remote, folder, and device name locally; cloud credentials remain in rclone's private configuration. Each device has a separate subfolder, so several computers can use the same cloud endpoint safely. For an off-site backup, use rclone's `crypt` remote wrapper so cloud-stored filenames and contents are encrypted.

Run `omarchy backup create` to upload a fresh archive. `omarchy backup restore --dry-run` shows the top-level home-directory items in the most recent archive, and `omarchy backup restore` asks before replacing matching files. It does not remove files that are absent from the backup. Backups exclude only regenerable caches and Trash plus rclone credentials and the cloud-backup configuration itself; set up the rclone remote on the restoring machine before downloading.

## Shared personal settings

Backups are per-device. Shared personal settings use a Git repository over SSH, so each device publishes a versioned `profiles/<hostname>` branch and shared `main` is an explicit merge of those profiles. Create an empty bare repository on your backup node, then connect it with `omarchy backup sync setup --repo 'user@host:omarchy-profile.git'`. Use `omarchy backup sync push` on the computer that has changes, `omarchy backup sync merge` to create the new shared latest profile, and `omarchy backup sync pull --dry-run` followed by `omarchy backup sync pull` on another machine. `omarchy backup sync history` shows all versions, while `omarchy backup sync rollback <commit>` makes an older version the new shared latest without deleting history.

Git combines independent files and non-overlapping edits automatically. When two machines edit the same setting incompatibly, the merge stops and reports a normal Git conflict instead of silently choosing a winner; resolve it deliberately, then rerun the merge. The profile includes keybindings, input and look-and-feel preferences, Omarchy shell settings and custom themes, terminal settings, and common developer-tool preferences. It deliberately leaves out monitor layout and autostart because those are device-specific.

Add extra relative paths to `~/.config/omarchy/backup/sync-paths`, one per line, to share another app's preferences. Push is explicit rather than automatic, so a change on one machine cannot silently overwrite a newer setting on another.

### Starting your own apps with the session

If you want something to run every time you log in — a sync daemon, a chat app, your own script — put it in `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start("my-service")
```

That starts the command as part of the session, so it's properly cleaned up when you log out again.

### Running scripts on system events

Omarchy fires hooks at a handful of moments, and you can hang your own scripts off them. They live in `~/.config/omarchy/hooks/<event>.d/`, one directory per event, and every executable file in there runs when the event happens:

| Event | When it runs |
| ----- | ------------ |
| `post-boot` | Right after the desktop has started |
| `post-update` | During `omarchy update`, after packages and migrations |
| `pre-refresh-pacman` | Before `omarchy refresh pacman` re-syncs the package config |
| `theme-set` | After a theme change (theme name in `$1`) |
| `font-set` | After a font change (font name in `$1`) |
| `battery-low` | When the battery gets low (percentage in `$1`) |

Each of those directories already holds a `.sample` file showing the shape of a hook — drop the `.sample` from the name to put it to work. To install a script you've written elsewhere, use `omarchy hook install post-boot ~/my-hook`, which copies it in and makes it executable.

### Adding your own menu entries

The Omarchy menu (`Super + Space`) can be extended with your own rows by editing `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Entries are keyed by a dotted id, and the id is what places them in the tree, so `personal` shows up on the root menu and `personal.notes` shows up inside it:

```jsonc
"personal": {"icon":"","label":"Personal"},
"personal.notes": {"icon":"󰎞","label":"Notes","action":"omarchy-launch-editor ~/notes"},
```

Reuse an existing id and you override that row instead of adding a new one. The file ships with all the available fields documented as comments.

### Adding your own shell exports, functions, and aliases

Omarchy ships with a bunch of ergonomic aliases and helpful functions, but it's very common to want to add your own. You should add both aliases, functions, and exports in `~/.bashrc`. This file will not be overwritten on updates. If you want to change any of the Omarchy defaults, you can also safely add them here.

### Changing internal Omarchy files

Look, this is your computer. You can do whatever you want with it, but I would advise against making changes to the files in `/usr/share/omarchy` directly. They belong to the Omarchy pacman package, so your changes will simply be overwritten on the next update. You're better off just overwriting any default values you don't like in the `~/.config/*` folder instead.

You can change just about everything that way, like the default keybindings. Just edit `~/.config/hypr/bindings.lua` to, say, replace [Obsidian](https://obsidian.md/) with [Joplin](https://joplinapp.org/) (install with `omarchy-pkg-add joplin-bin`):

```
hl.unbind("SUPER + SHIFT + O")
o.bind("SUPER + SHIFT + O", "Joplin", "joplin-desktop")
```

If you insist on hacking on the internal Omarchy files, switch to the dev channel via _Update > Channel > Dev_. That links Omarchy to a git checkout of the source code in `~/omarchy`, which you're free to change to your heart's content. Ain't nobody here to tell you what to do!

### Resetting any changes

If you end up making a mess of the configurations, you can always revert them to the defaults via _Update > Config_ in the Omarchy menu. Or by running `omarchy reinstall configs` to reset everything.
