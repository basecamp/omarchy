# Notifications

The shell is the notification daemon: `shell/plugins/notifications/Service.qml`
hosts a Quickshell `NotificationServer` that claims `org.freedesktop.Notifications`
on the session bus. There is no dunst or mako — anything that speaks the
freedesktop notification protocol (notify-send, libnotify apps, Chromium web
apps) lands in the shell, which renders it as a toast card stacked in the
top-right corner. The pure decision logic lives in `NotificationLogic.js`,
which is also loadable from Node so `test/shell.d/` can exercise it without
a compositor.

The end-user view (hotkey notices for time, battery, weather) is in
`manual/10-notices.md`; this document is the system shape behind it.

## Toast lifecycle

A toast lives on screen for at least 5s (low), 8s (normal), or forever
(critical), stretched up to 30s if the sender asked for a longer
`expire_timeout`. Hovering pauses the countdown, and a content update restarts
it — new text deserves a full look. Left-click invokes the default action,
right-click or the hover-revealed close button dismisses.

Every on-screen popup is mirrored to its own file under
`~/.local/state/omarchy/notifications/` (one JSON line per file, named
`<timestamp>-<id>.json`), so live toasts survive the shell restart that
`omarchy-update` performs. When a toast leaves the screen — expiry, dismissal,
or click — its file moves into `notifications/history/`, trimmed to the newest
ten. That directory *is* the history: `showHistory` replays exactly what has
been moved in there. Referenced avatars/images are copied into
`notifications/images/`, because senders delete their originals on close.

`replaces_id` updates never produce a second notification signal: the server
writes new content onto the object the service already holds, so the service
watches the object's property-change signals and rewrites the row and its file
in place, under the popup's original file identity. Restored rows carry ids
from a dead server generation (ids restart from 1 each shell process), so
they are keyed by timestamp+id and never matched against live objects — a
fresh notification reusing an old id must not dismiss or replace them.

## Silencing

Do-not-disturb is a single boolean, persisted as the `dnd` key in
`~/.local/state/omarchy/notifications.json` and toggled via shell IPC
(`omarchy-shell notifications toggleDnd` / `setDnd` / `dndState`).
`omarchy-toggle-notification-silencing` wraps the toggle and refreshes the
bar's `omarchy.indicators` widget, whose Dnd indicator binds directly to the
service's `doNotDisturb` property.

Two kinds of notification punch through DND, chosen to be intentional and
rare:

- `app_name` = `omarchy-action` — Omarchy's own user-action confirmation
  toasts ("Theme changed"). The user just did something; their feedback shows.
- urgency critical *and* `app_name` = `notify-send` — bare-CLI emergency
  alerts. Critical alone is not enough, because chat apps abuse it to force
  visibility; they set `app_name` to their brand, which fails this rule.

A silenced notification that anyone might look back at is written straight
into history — "what did I miss while silenced" is what history is for.
Ephemeral ones (the freedesktop `transient` hint, or an `app_name` of
`notify-send`/`omarchy-action`) are dropped entirely.

## The sender contract

`bin/omarchy-notification-send` is the one way Omarchy code sends
notifications — never raw `notify-send`. It calls
`org.freedesktop.Notifications.Notify` directly over the session bus (via
`busctl --user`), so each value is one typed D-Bus parameter and there is no
argv layer that could reinterpret a relayed headline as an option or a hint. Its
flags map onto that call:

| Flag | Becomes | Meaning |
|---|---|---|
| `-g` / `--glyph` | hint `omarchy-glyph` | Nerd Font glyph for the icon slot when no image icon resolves |
| `--exec <program> [args…]` | hint `omarchy-exec-argv` | the click command; consumes the rest of the line, so it comes last. Each word is a discrete argument the shell runs without re-parsing (see below) |
| `--image` | hint `image-path` | the standard freedesktop image hint |
| `-i` / `--icon` | `app_icon` | themed icon name for the toast |
| `--app-name` | `app_name` | defaults to `omarchy-action` |
| `-u` / `--urgency` | hint `urgency` (byte) | `low`/`normal`/`critical`; defaults to `low` |
| `-t` / `--expire-time` | `expire_timeout` | milliseconds on screen; server default otherwise |

Unknown flags are a hard error, not a silent pass-through: `--exec` is the only
door to a click command, and there is no generic option pass-through to smuggle
one through.

The defaults are the point: an unadorned `omarchy-notification-send "Done"`
is a low-urgency user-action toast that pops through DND and is treated as
ephemeral noise when silenced.

The click command is deliberately not a libnotify action. An action keeps the
sender blocked waiting for `ActionInvoked`, and dies unanswered whenever the
shell restarts underneath it — the installer toasts restart the shell as their
first act. Carrying the command as a hint means the shell executes the click
itself (detached, so the command outlives the shell process) from the copy it
keeps with the popup, which the persistence files preserve: a restored toast
clicks through exactly like a live one, and oneshot senders can exit
immediately. For third-party clients the click falls back to the libnotify
`default` action while the sender is alive, then to focusing the sender's
window by class via `omarchy-hyprland-focus-app` — chat apps rarely register
an action and just expect click-to-jump.

### Click commands are argv, never shell strings

`--exec` consumes the rest of the line as the click command:

```bash
omarchy-notification-send "Download complete" "$title" --exec mpv -- "$file"
```

The caller's shell has already split those words into discrete arguments, and a
quoted argument (`"$file"`) stays one argument even with spaces. On the shell
side they are run through `Util.execArgv`, which invokes `bash -lc 'exec "$@"'`
with the arguments as **positional parameters** — never interpolated into the
script text. bash expands `"$@"` without re-tokenizing or re-evaluating it, so a
value carrying data an attacker controls — a downloaded video's title, a
received filename, a crashed process's name — is only ever a single argument and
can never be reparsed as a command. The login shell keeps the PATH and session
environment that GUI click targets (the screenshot editor, mpv, xdg-open) expect.

The critical rule: **the splitting must happen at the call site, not inside the
tool.** Passing a single quoted string (`--exec "mpv $title"`) and letting the
tool whitespace-split it would hand argument boundaries to whoever controls the
string's content — a title with a space could inject an extra option or program.
So `--exec` refuses a lone quoted-string argument and points at the unquoted
form. There is no "take a command string and sanitize it" path; that is the
escaping trap (string-concatenated SQL) the yt-dlp title RCE exploited.

The shell fails closed on a malformed argv hint (it must be a JSON array of
strings whose program is present and not a leading-dash option) rather than
running anything it can't validate. A caller can still deliberately name a shell
as the program (`--exec sh -c …`), but that runs code because the *developer*
wrote it, not because attacker data became a command — a reviewable red flag
(greppable as `--exec sh`/`--exec bash`), not an injection. Insulating against a
native same-user process is out of scope: it already runs with your privileges
and needs no notification to execute code. What is fully closed is untrusted
*content* — web notifications can't set the exec hint at all, and any relayed
title/filename is confined to inert argument data.

The sender keeps that last part true structurally rather than leaving it to each
caller. Because it calls `Notify` directly, the headline and description are
typed string parameters — a relayed value like `--hint=…` or `-rf` is the
summary or body, never an option or a hint, and there is no argv/option layer
(no `notify-send`) left to reinterpret it. `--exec` is the only thing that can
build the `omarchy-exec-argv` hint. (The leading `--` on the `busctl` call is a
belt for `busctl`'s own getopt, which would otherwise read a dash-leading value
as a `busctl` option; the summary/body themselves are never parsed as options.)

## Helper commands

- `omarchy-notification-wait [timeout]` — polls until the shell answers IPC
  *and* has claimed the bus name. Anything sending near session start or a
  shell restart uses it, or the toast is sent into the void.
- `omarchy-notification-dismiss <summary>` — dismiss by summary substring,
  used by the first-run toasts once their action has been clicked.
- `omarchy-notification-time` / `-battery` — the hotkey notices: one-line
  low-urgency glyph toasts wrapping `date` and `omarchy-battery-status`.
- `omarchy-notification-weather` — despite the name, not a sender: it toggles
  the `omarchy.weather` shell panel.

Keybindings live in `default/hypr/bindings/utilities.lua`: `Super+comma`
variants map to the IPC methods `dismissOne`, `dismissAll`, `invokeLast`,
`showHistory`, and the silencing toggle.

## How subsystems plug in

Everything goes through the same sender contract, so the pieces are small:

- **Low battery** — `omarchy-battery-low` sends a critical toast and runs the
  `battery-low` hook.
- **Crash capture** — `omarchy-crash-watch` follows the systemd-coredump
  journal stream and announces each crashed program (deduped per minute) as a
  critical toast whose click runs `omarchy-agent-crash` (via `--exec`, so a
  hostile process name stays a discrete argument). It waits for the
  server first: a shell crash takes the notification server down with it, and
  that crash is the one most worth reporting.
- **Pending migrations** — `omarchy-migrate-notify` (from its user service
  after `graphical-session.target`) waits for the server, then sends a
  critical toast whose click opens a terminal running `omarchy-migrate`,
  falling back to printing in the terminal if the hand-off fails.

## Reminders

Reminders ride on notifications rather than being their own daemon.
`bin/omarchy-reminder <minutes> [message]` creates a transient systemd user
timer via `systemd-run --user --collect --on-active=<minutes>m` under the
unit name `omarchy-reminder-<minutes>m-<epoch>`; the timer's payload sends the
reminder toast, deletes its message file, and refreshes the bar indicator.
Custom messages are stashed in `$XDG_RUNTIME_DIR/omarchy-reminders/<unit>.message`
since a unit name cannot carry arbitrary text. `--collect` means fired timers
leave nothing behind.

The state therefore lives entirely in systemd: `show` and `clear` enumerate
`systemctl --user list-timers "omarchy-reminder-*.timer"` — `show` as a
summary toast, `show --json` as the JSON the bar's Reminder indicator polls
(refreshed by the same `omarchy-shell -q omarchy.indicators refresh` call the
timers and mutations make). `omarchy-reminder -i` summons the
`omarchy.reminders` overlay (`shell/plugins/reminders/ReminderFlow.qml`), a
two-step minutes/message prompt that shells back out to `omarchy-reminder` to
do the setting.
