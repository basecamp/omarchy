# The Top Bar

The strip along the top of your screen is the Omarchy bar. It's not a bolted-on status bar but part of the Omarchy shell, the single long-running Quickshell process that also draws the menu, the notifications, the OSD popups, and the lock screen. That's why it themes perfectly with everything else and why a panel opens instantly instead of spawning a new app.

It's also the one piece of the desktop that's always on screen, so it's worth knowing what all those little glyphs do.

## What's on it by default

The bar has three sections. On the left sits the Omarchy logo (the menu launcher) and the workspace indicators. In the center you get the status indicators, the clock, the keyboard layout, the weather, and an Omarchy update badge. On the right: the system tray, agents, bluetooth, network, audio, display, and power.

A few of those only show up when they have something to say. The keyboard layout appears only if you've configured more than one layout. The update badge appears only when there's an Omarchy update waiting. And the agents icon appears the first time Omarchy finds AI coding usage on the machine (see [AI](17-ai.md)).

## Clicking around

Nearly every widget does something on left, right, and middle click, and several respond to scrolling. This is the part people miss — the right and middle buttons are where a lot of the good stuff hides.

| Widget | Left | Right | Middle / scroll |
| --- | --- | --- | --- |
| Menu | Omarchy menu | New terminal | — |
| Workspaces | Focus that workspace | — | — |
| Clock | Calendar popup | Cycle the label format | Middle: timezone picker |
| Weather | Forecast popup | Full weather as a notification | Middle: refresh |
| Audio | Audio panel | Mute | Middle: panel · scroll: volume |
| Microphone | Mute the mic | — | Middle: audio panel · scroll: input volume |
| Network | Network panel | — | — |
| Bluetooth | Bluetooth panel | Toggle the radio | — |
| Display | Display panel | — | Scroll: brightness |
| Power | Power panel | Toggle the battery percentage | — |
| Media | Play/pause | Cover-art popup | Middle: next · scroll: prev/next |
| Agents | Agents panel | Launch your agent | Middle: next subscription |
| News | Omarchy news reader | Refresh the feed | — |
| Tray | Hover to reveal the drawer | Right on the chevron to manage | — |
| Omarchy update | Run the update | — | — |

Not everything in that table is on your bar out of the box. The media widget (MPRIS now-playing, with a scrolling track and artist) and the microphone widget are both built in but off by default — add them if you want them, as described below.

## The panels

Clicking a bar icon opens a panel, which is a proper popup with sliders, lists, and keyboard navigation rather than a tooltip. Each one also has a hotkey, so you never have to aim at a 16-pixel glyph:

| Hotkey | Panel |
| --- | --- |
| `Super + Ctrl + A` | Audio |
| `Super + Ctrl + W` | Network |
| `Super + Ctrl + B` | Bluetooth |
| `Super + Ctrl + D` | Display |
| `Super + Ctrl + P` | Power |
| `Super + Ctrl + Alt + D` | Calendar |
| `Super + Alt + N` | Omarchy News |
| `Super + Ctrl + 1-9` | Toggle the nth panel in the right section |

The panels aren't read-outs. They're where you actually do the thing:

- **Audio** has a master volume slider, an output-device picker, and a per-app mixer, so you can turn down that one browser tab without touching everything else.
- **Network** scans for Wi-Fi, shows signal strength, connects, and lets you pick a DNS provider.
- **Bluetooth** lists your devices with connect/disconnect and battery levels.
- **Power** shows battery stats, switches power profiles (it remembers a separate choice for battery and AC), and prints some system info.
- **Display** carries a brightness slider, text size, monitor scaling presets, and — when you have more than one screen — per-monitor controls. See [monitors](33-monitors.md) for the deeper story.
- **Clock** opens a month grid with ISO week numbers and month stepping.
- **News** reads official Omarchy and Omacom Foundation announcements from the RSS feed in a two-pane desktop reader. It refreshes every 15 minutes by default, and the bar icon marks unread announcements. Its widget settings can also add the curated BBC News feed; use `[` and `]` to switch between sources in the reader.

Every panel takes the keyboard as well as the mouse: arrows move, Return activates, Tab steps to the neighbouring panel, and Escape closes.

`Super + Ctrl + 1-9` counts panels left to right in the right section, skipping the tray since it has no panel of its own. So the number matches the icon you'd point at.

### Tailscale and Dropbox

Two more widgets appear on the bar only once you install the matching service from **Install → Service**, and both are worth knowing about because they do more than report status.

The **Tailscale** panel connects and disconnects the tailnet, switches between accounts, and picks an exit node (your own machines and Mullvad regions both show up in that list). It also browses your machines — and with one selected, `s` sends files to it over Taildrop, which is the fastest way to move a file to your phone or another laptop. `c` copies the machine's IP, `n` its name, and `d` its full DNS name. There's a send button on each machine row too, if you'd rather click. The same thing from the terminal is `omarchy tailscale send <machine> [file...]`.

The **Dropbox** panel handles login, shows how much storage you've used, and lists recently synced files.

Removing either service takes its widget back off the bar.

## Indicators

The little cluster in the center is the indicators widget. These are status glyphs for modes you've turned on: do not disturb, night light, a queued [reminder](09-reminders.md), an active screen recording, stay awake, and [dictation](11-text-extraction-dictation.md). They light up when the mode is active and otherwise stay out of the way — hover the center of the bar to peek at the inactive ones. Clicking an indicator toggles that mode.

If you'd rather they were always visible, set `alwaysShow` to `true` on the widget. And if you only care about some of them, list the ones you want in `items`: `["Dnd", "Reminder", "NightLight"]`. You can have more than one indicators widget, so different sections can show different subsets.

## Rearranging the bar

The bar configures itself. You don't have to open a config file to move things.

Grab an empty patch of the bar around the center and drag it toward another screen edge, and the bar moves there — left, right, top, or bottom all work, and every widget adapts (vertical bars fall back to compact icon-only forms). A click-and-hold starts the same drag. Double-left-click that same empty space to toggle transparency. And drag any widget to reorder it or throw it into another section.

If you'd rather pick from a menu, **Style → Menu Bar** has both position and transparency.

The same things have commands, which is what you want for a [dotfiles](31-dotfiles.md) setup:

```bash
omarchy bar position bottom
omarchy bar transparent toggle
omarchy bar move omarchy.clock --section center --index 0
omarchy bar set omarchy.clock format "HH:mm"
omarchy bar defaults          # back to the shipped layout
```

To add or remove a widget entirely, use the plugin commands. `omarchy plugin list` prints every widget the shell knows about with its id, and then:

```bash
omarchy plugin enable omarchy.media --section center
omarchy plugin disable omarchy.weather
```

## Hiding the bar

`Super + Shift + Space` toggles the bar off and back on without killing the shell — panels and hotkeys keep working, you just get the pixels back. It's also in the menu under **Trigger → Toggle → Menu Bar**.

## The config file

All of it is stored in `~/.config/omarchy/shell.json`, under the `bar` key. Here's a trimmed version:

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": [{ "id": "omarchy.menu" }, { "id": "omarchy.workspaces" }],
      "center": [{ "id": "omarchy.clock", "format": "HH:mm" }],
      "right": [{ "id": "omarchy.audio" }, { "id": "omarchy.power" }]
    }
  }
}
```

Every widget is one entry in one of the three layout arrays, and its settings sit inline on that entry — there's no separate settings file and no `config` sub-object. The clock's `format`, `formatAlt` (what right-click cycles to), and `verticalFormat` all live right there on `{ "id": "omarchy.clock" }`.

`centerAnchor` names the one center widget that gets pinned to the exact center of the screen, with the others flanking it. That's how the clock stays dead center even as the weather and update badge come and go. Set it to an empty string and the center list is just centered as a group instead.

One rule worth internalizing: **once you have your own `shell.json`, it's canonical**. Until you customize anything, the shell reads Omarchy's default file. The moment you drag a widget, run `omarchy bar`, or edit the file yourself, you own it — there's no deep merge, so new default widgets in future Omarchy releases won't appear on your bar automatically. `omarchy bar defaults` puts the shipped layout back whenever you want a clean slate.

The same file also holds your idle timings at the top level, outside the `bar` key: `idle.screensaver` and `idle.lock`, both in seconds since you went idle. So the default screensaver kicks in at 150 seconds and the lock at 300.
