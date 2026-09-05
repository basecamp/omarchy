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

### Starting your own apps with the session

If you want something to run every time you log in — a sync daemon, a chat app, your own script — put it in `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start("my-service")
```

That starts the command as part of the session, so it's properly cleaned up when you log out again.

### Running scripts on system events

Omarchy fires hooks at a handful of moments, and you can hang your own scripts off them. User hooks live under `~/.config/omarchy/hooks/`:

| Event | When it runs |
| ----- | ------------ |
| `post-boot` | Right after the desktop has started |
| `post-update` | During `omarchy update`, after packages and migrations |
| `pre-refresh-pacman` | Before `omarchy refresh pacman` re-syncs the package config |
| `theme-set` | After a theme change (theme name in `$1`) |
| `font-set` | After a font change (font name in `$1`) |
| `battery-low` | When the battery gets low (percentage in `$1`) |

For each event, the runner supports one flat `~/.config/omarchy/hooks/<event>` hook plus any non-hidden regular files directly inside `~/.config/omarchy/hooks/<event>.d/`. The flat hook runs first, then the directory files run in filename order. Nested directories, names beginning with `.`, and directory entries ending in `.sample` are skipped. Event names must start with an ASCII letter or number and can otherwise contain ASCII letters, numbers, `.`, `_`, and `-`.

Each event directory already holds a `.sample` file showing the shape of a hook — drop the `.sample` from the name to put it to work. To install a script you've written elsewhere, use `omarchy hook install post-boot ~/my-hook`, which preserves its basename, copies it in, and makes it executable. Rename a hidden script or one ending in `.sample` before installing it.

Software packages can provide the same flat and directory forms under `$OMARCHY_PATH/hooks/` or `<data-dir>/omarchy/hooks/`, where `<data-dir>` is an absolute entry in `XDG_DATA_DIRS`. The default package roots are `/usr/local/share/omarchy/hooks/` and `/usr/share/omarchy/hooks/`; `XDG_DATA_HOME` is not searched. The active Omarchy tree runs first, package roots run in `XDG_DATA_DIRS` order, and your hooks under `~/.config/omarchy/hooks/` always run last so they can react to or customize packaged behavior. For safety, package hook paths cannot contain symlinks, must be controlled by root or your account, and cannot be shared-writable at or below the package hook root. A sticky shared directory such as `/tmp` is supported only as an ancestor above that root.

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
