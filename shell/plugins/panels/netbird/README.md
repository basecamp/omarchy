# NetBird Omarchy Widget

Native Omarchy bar widget for NetBird.

## Features

- Shows NetBird connection state in the bar
- Left click opens a keyboard-friendly panel
- Right click toggles NetBird on/off
- Switch between NetBird profiles when multiple are available
- Browse machines from `netbird status --json`
- Copy a machine's NetBird IP, host name, or FQDN

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row
- `c`: copy selected peer IP
- `n`: copy selected peer name
- `d`: copy selected peer FQDN
- `t`: toggle NetBird
- `r`: refresh status
- `esc`: close

## Requirements

- `netbird` CLI on `PATH`
- `wl-copy` for clipboard copy actions

## Icon

Renders a glyph-based icon matching the Omarchy bar aesthetic, with crossed-out and warning states for disconnected and needs-login states.

## Add to the bar

This widget ships as first-party plugin `omarchy.netbird`. Add it with `omarchy plugin enable omarchy.netbird`, then place it with `omarchy bar move omarchy.netbird` if desired.