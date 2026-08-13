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
