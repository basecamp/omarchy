# Tailscale Omarchy Widget

Native Omarchy bar widget for Tailscale.

## Features

- Shows Tailscale connection state in the bar
- Left click opens a keyboard-friendly panel
- Right click toggles Tailscale on/off
- Switch between available Tailscale connections when multiple are available
- Browse machines from `tailscale status --json`
- Copy a machine's Tailscale IP, host name, or DNS name
- Send files to a machine with Taildrop, when the tailnet allows file sharing
- Send the clipboard contents to a machine with Taildrop (an image goes over as itself, files copied in a file manager as themselves, anything else as a small text file; password-manager copies are refused)

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row
- `c`: copy selected peer IP
- `n`: copy selected peer name
- `d`: copy selected peer DNS name
- `s`: send files to selected peer
- `v`: send clipboard contents to selected peer
- `t`: toggle Tailscale
- `r`: refresh status
- `esc`: close

## Requirements

- `tailscale` CLI on `PATH`
- `wl-copy` and `wl-paste` for the clipboard actions
- Taildrop enabled for the tailnet, to send files

## Receiving files

Incoming Taildrop files are saved to `~/Downloads` by the
`omarchy-tailscale-receive` service, which announces each one with a
notification (an image preview when the file is an image, and a click to open
it). A clipboard text drop is announced as click-to-copy instead, putting the
text straight on this machine's clipboard. The Tailscale service install
enables it; `omarchy tailscale receive` runs the same loop by hand.

## Icon

Renders the Tailscale mark natively as a theme-colored 3×3 dot grid, matching the official SVG silhouette while avoiding tiny-SVG rendering quirks in the bar.

## Add to the bar

This widget ships as first-party plugin `omarchy.tailscale`. Add it with `omarchy plugin enable omarchy.tailscale`, then place it with `omarchy bar move omarchy.tailscale` if desired.
