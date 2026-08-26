# NetBird Omarchy Widget

Native Omarchy bar widget for [NetBird](https://netbird.io/).

## Features

- Shows NetBird connection state in the bar
- Left click opens a keyboard-friendly panel
- Right click connects or disconnects, middle click refreshes
- Switch between NetBird profiles when the CLI supports them and more than one exists
- Browse peers from `netbird status --json`, including idle ones
- Select and deselect network routes, with exit nodes listed first
- Copy a peer's NetBird IP, host name, or full domain name
- Warns when the daemon is down, when this user cannot reach its socket, and when system DNS overrides the DNS NetBird serves

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row
- `c`: copy selected peer IP
- `n`: copy selected peer name
- `d`: copy selected peer domain name
- `t`: connect or disconnect NetBird
- `r`: refresh status
- `a`: open the NetBird admin console
- `esc`: close

## Requirements

- `netbird` CLI on `PATH`, with a running `netbird.service`
- The daemon socket has to be reachable by the desktop user; the panel says so plainly when it is not
- `wl-copy` for clipboard copy actions

## CLI surface

The widget shells out rather than speaking to the daemon directly:

| What | Command |
|---|---|
| Status and peers | `netbird status --json` |
| Connect / disconnect | `netbird up` / `netbird down` |
| Routes | `netbird routes list --json`, then `netbird routes list`, then `netbird networks list` |
| Route selection | `netbird <routes\|networks> select\|deselect <id>` |
| Profiles | `netbird profile list --json`, `netbird profile select <name>` |

NetBird has renamed and extended this surface across releases, so the route
lookup walks those three spellings once, latches onto whichever the installed
CLI accepts, and stops asking if none of them do. Profiles work the same way: a
CLI that has never heard of them simply shows no profile section rather than an
error. `Model.js` holds every parser, and the shapes it accepts are pinned by
`test/shell.d/netbird-test.sh`.

## DNS

`omarchy dns <provider>` pins DNS through a NetworkManager
`[global-dns-domain-*]` block, which NetworkManager applies ahead of every
other source — including the split DNS a VPN installs. A machine pinned to
Cloudflare or Google can therefore stop resolving the domains NetBird serves
while NetBird itself still reports a healthy connection.

The panel notices that combination — NetBird carrying enabled nameserver groups
plus a non-DHCP system provider — and offers to hand DNS back to DHCP.
`omarchy-install-service-netbird` prints the same warning at install time.

## Icon

Renders a NetBird-style mesh natively as a theme-colored hub with three linked
peers, which avoids the tiny-SVG rendering quirks Qt has in bar slots. The
Tailscale widget next door draws its mark the same way.

## Add to the bar

This widget ships as first-party plugin `omarchy.netbird`. Add it with `omarchy plugin enable omarchy.netbird`, then place it with `omarchy bar move omarchy.netbird` if desired.
