# Terminal Configuration

Use this guide for user configuration of Alacritty, Foot, Kitty, or Ghostty.

## User Files

```text
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

Inspect the current user file and the terminal's installed version and help
before writing version-sensitive settings. Preserve a working terminal session
while testing a configuration that could prevent new windows from opening.

## Change Loop

1. Edit only the active terminal's user configuration.
2. Run `omarchy restart terminal` to ask supported running terminals to reload.
3. Open a new window for Foot, which picks up changes only in new processes.
4. Exercise the changed font, colors, bindings, shell, or window behavior in a new terminal window.
5. Inspect terminal output for configuration warnings or rejected keys.

`omarchy restart terminal` reloads configuration; it does not terminate and
relaunch the user's terminal sessions.

Terminal work is complete when a new window opens successfully, the requested
setting is observable, and no relevant configuration warning remains. If the
new configuration fails, restore the preserved copy from the still-working
session and repeat the check.
