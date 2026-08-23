# Plugins for Omarchy

A community plugin is just a public git repo with a `manifest.json` at its root — [Shell Plugins](32-shell-plugins.md) covers that lifecycle in full. This page walks through a real one, OmaSwitch, so you can see how a third-party plugin behaves in practice: how it's installed, wired into a keybinding, and used day to day.

## OmaSwitch

OmaSwitch is a Windows-style `Alt+Tab` switcher for Omarchy with live window previews. It lists your recently used windows in a fast, keyboard-first overlay, lets you cycle with `Alt+Tab` or filter by typing, and shows a live preview of the highlighted window before you switch. It follows your active theme and runs entirely inside `omarchy-shell` — no daemon, no extra package, no privileges.

Install it from its git repo:

```
omarchy plugin add https://github.com/piyush97/omaswitch.git --enable
```

That clones the repo into `~/.config/omarchy/plugins/piyush.omaswitch/`, validates the manifest, and enables the plugin. Nothing else is installed or executed.

### Make it your Alt+Tab

Omarchy binds `Alt+Tab` to direct window cycling by default. To hand the key over to OmaSwitch, replace those two bindings in `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "OmaSwitch", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":1}'")
o.bind("ALT + SHIFT + TAB", "OmaSwitch (reverse)", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":-1}'")
```

Then reload and check Hyprland accepts it:

```
hyprctl reload
hyprctl configerrors
```

`configerrors` should print nothing. If you'd rather keep Omarchy's default bindings, bind either summon command to a different key instead.

### Using it

| Shortcut | What it does |
|---|---|
| `Alt+Tab` | Open the switcher and move to the next recent window |
| `Alt+Shift+Tab` | Open the switcher and move backward |
| `Tab`, `Down`, `Right` | Select the next window |
| `Shift+Tab`, `Up`, `Left` | Select the previous window |
| Type | Filter by title, application, or workspace |
| `Backspace` / `Ctrl+Backspace` | Delete a character / word from the search |
| `Ctrl+U` | Clear the search |
| `Enter` or click | Focus the selected window |
| `Esc` or click outside | Close without switching |

To open the searchable picker directly:

```
omarchy-shell shell toggle piyush.omaswitch
```

Live previews rely on Hyprland's `hyprland-toplevel-export-v1` protocol. If it isn't available the switcher still works — it simply shows the list full-width without the preview pane.

### Keeping it current

Update, disable, or remove it the same way as any plugin:

```
omarchy plugin update piyush.omaswitch --yes
omarchy plugin disable piyush.omaswitch
omarchy plugin remove piyush.omaswitch --yes
```

### Troubleshooting

- **The plugin isn't listed** — rescan and re-check: `omarchy-shell shell rescanPlugins`, then `omarchy plugin list --json`.
- **Alt+Tab still cycles windows directly** — the unbind didn't take. Confirm `hyprctl configerrors` is clean and `omarchy menu keybindings --print` shows the OmaSwitch bindings.
- **The switcher opens without a preview** — the selected window may not be capturable, or `hyprland-toplevel-export-v1` is missing. This is expected fallback behavior; the list stays fully usable.
