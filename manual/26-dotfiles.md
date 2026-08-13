# Dotfiles

Omarchy is primarily configured through the so-called dotfiles that live in `~/.config`. Those are considered your files for your changes. The files that live in `~/.local/share/omarchy` belong to Omarchy itself, and you ideally shouldn't be messing with those. If you need to change anything in `~/.local/share/omarchy`, you should be overwriting the value in `~/.config` instead.

Almost everything can be edited through _Setup > Configs > [process]_ through the Omarchy menu (`Super + Alt + Space`). When you do it this way, any process that needs restarting after config edits automatically will be after you quit the Neovim editor (`:wq`, remember!).

Here's a list of the key files in `~/.config` and what they control:

| File                  | Purpose              |
| ----------------------- | --------------------- |
| `~/.config/hypr/hyprland.conf` | Controls keybindings, default apps, and everything Hyprland. [Learn more about Hyprland configs](https://wiki.hypr.land/Configuring/).  |
| `~/.config/hypr/monitors.conf` | Controls your monitors, resolution, and position. |
| `~/.config/hypr/hypridle.conf` | Controls your idle/sleep settings. Shouldn't need touching. |
| `~/.config/hypr/hyprlock.conf` | Controls your lock screen, but this is symlinked to your theme for styling.  |
| `~/.config/waybar/config.jsonc` | Controls your top bar that's run with waybar.  [Learn more about Waybar configs](https://github.com/Alexays/Waybar/wiki/Configuration). |
| `~/.config/waybar/style.css` | Controls your top bar design, but it's symlinked to your theme. |
| `~/.config/walker/config.toml` | Controls your launcher that's run with Walker. |
| `~/.config/alacritty/alacritty.toml` | Controls your terminal. |
| `~/.config/uwsm/default` | Controls your default $EDITOR. Requires relaunching Hyprland when changed. |
| `~/.XCompose` | Defines your quick-access emoji and name/email autocomplete. Make sure to run `omarchy-restart-xcompose` after making changes. |

If you end up making a lot of changes to tweak your own setup, it's a good idea to backup all these dotfiles. [Stow is a great way to do that](https://www.youtube.com/watch?v=NoFiYOqnC4o).

### Adding your own shell exports, functions, and aliases

Omarchy ships with a bunch of ergonomic aliases and helpful functions, but it's very common to want to add your own. You should add both aliases, functions, and exports in `~/.bashrc`. This file will not be overwritten on updates. If you want to change any of the Omarchy defaults, you can also safely add them here.

### Changing internal Omarchy files

Look, this is your computer. You can do whatever you want with it, but I would advise against making changes to the files in `~/.local/share/omarchy` directly. It'll make it harder for you to upgrade in the future. You're better off just overwriting any default values you don't like in the `~/.config/*` folder instead.

You can change just about everything that way, like the default keybindings. Just edit `~/.config/hypr/hyprland.conf` to, say, replace [Obsidian](https://obsidian.md/) with [Joplin](https://joplinapp.org/) (install with `yay -S joplin-bin`):

```
bind = SUPER SHIFT, O, exec, joplin
```

If you insist on changing internal Omarchy files, you'll need to commit your changes before you can use `omarchy update`. You can do that with `gcam "Look ma! I'm breaking the rules!"` from inside the `~/.local/share/omarchy` directory. Ain't nobody here to tell you what to do!

### Resetting any changes

If you end up making a mess of the configurations, you can always revert them to the defaults via _Update > Config_ in the Omarchy menu. Or by running `omarchy reinstall configs` to reset everything.
