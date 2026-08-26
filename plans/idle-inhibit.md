# Plan: Idle inhibit — honor D-Bus screensaver inhibits again

Revision 1.

## Problem

Quattro replaced `hypridle` with the Quickshell idle service. hypridle registered
`org.freedesktop.ScreenSaver` on the session bus; the Quickshell service does
not, and `IdleMonitor { respectInhibitors: true }` honors only the Wayland
`zwp_idle_inhibit_manager_v1` protocol. An application that requests its inhibit
over D-Bus therefore has it dropped on the floor:

- Firefox and Zen play a video → nothing owns `org.freedesktop.ScreenSaver` →
  the screensaver launches over the playing video, then the session locks
  (#6475, #7220, #7199 — 42 👍 across the three).
- Chromium-family browsers take *two* inhibits for video (ScreenSaver +
  `org.freedesktop.PowerManagement.Inhibit`) and lose both.
- VLC inhibits through `org.freedesktop.ScreenSaver` at the legacy `/ScreenSaver`
  object path and loses it.

The applications are behaving correctly; nobody is listening. Every
desktop environment owns these names; Omarchy 3 did too, through hypridle.

## What the browsers actually do (verified from source, not assumed)

The client side dictates several constraints that rule designs out:

- **Chromium** (`power_save_blocker_linux.cc`) probes with
  `org.freedesktop.DBus.NameHasOwner` before calling `Inhibit`.
  `NameHasOwner` does **not** trigger D-Bus activation. If the name is
  unowned, Chromium logs "we just ignore them" and never inhibits — no retry,
  no fallback. VLC behaves the same (it only calls backends whose name has an
  owner).
- **Firefox** (`WakeLockListener.cpp`) rotates backends — portal →
  `org.freedesktop.ScreenSaver` at `/ScreenSaver` →
  `org.freedesktop.PowerManagement.Inhibit` → `org.gnome.SessionManager` —
  retrying once per state transition when a backend errors.
- **Object paths split by client**: VLC and Firefox use the legacy `/ScreenSaver`
  path (KDE ≤ 4.11 compatibility, codified in the spec's design notes);
  Chromium uses `/org/freedesktop/ScreenSaver`. A responder must export the
  interface on **both**.
- **Lifetime**: the spec says inhibition ends on `UnInhibit` *or when the
  application disconnects from the bus*. A browser crash must not leave the
  session permanently uninhibited; hypridle reaps by watching
  `NameOwnerChanged` with an empty new owner, and this design does the same.

## Rejected approaches

- **D-Bus service activation** (`~/.local/share/dbus-1/services` `.service`
  file, daemon spawned on first `Inhibit`): dead on arrival given the
  `NameHasOwner` probing above — Chromium and VLC would never trigger it, and
  they are the majority of the reports. Activation also restarts from zero
  state (inhibits silently forgotten) whenever the daemon exits.
- **Bridging D-Bus inhibits to a Wayland inhibitor held by a helper**
  (`zwp_idle_inhibit_manager_v1` in a bridge process): the protocol binds an
  inhibitor to a surface, and sway explicitly ignores inhibitors whose surface
  is not visible — a bare never-mapped surface from a headless bridge does not
  count. Layer-shell trickery to keep an invisible-but-"visible" surface is
  fragile, compositor-specific, and untestable without a session. The ext-idle
  notify v2 `get_input_idle_notification` clients ignore inhibitors anyway.
- **Running hypridle alongside the Quickshell idle service**: two idle daemons
  racing to run screensaver/lock actions; hypridle holds its inhibit state
  internally where the Quickshell service cannot see it.
- **Teaching Quickshell to serve D-Bus**: Quickshell 0.3.1 has no D-Bus service
  registration API (client-side calls only; serving `org.freedesktop.ScreenSaver`
  is an open upstream discussion). Waiting on upstream leaves the bug open.
- **`systemd-inhibit` / logind**: logind's `idle` inhibitor is not consulted by
  the Quickshell `IdleMonitor`, and browsers do not use it for display idle.

## Chosen design: a small always-on responder that owns the names and publishes state; the idle service gates on it

Two components, one contract.

### 1. `omarchy-idle-inhibit-daemon` (python3 + PyGObject, already a base dependency)

A session-bus responder owned by a systemd user unit
(`omarchy-idle-inhibit.service`, `WantedBy=graphical-session.target`, the
crash-watch/migrate-notify pattern) so it is running before any browser probes:

- Owns **`org.freedesktop.ScreenSaver`**, exporting `Inhibit(ss) → u`,
  `UnInhibit(u)`, and the KDE-compat extras `GetActive() → b` +
  `ActiveChanged(b)` signal, on **both** `/org/freedesktop/ScreenSaver` and
  `/ScreenSaver`.
- Owns **`org.freedesktop.PowerManagement`**, exporting `Inhibit(ss) → u`,
  `UnInhibit(u)`, `HasInhibit() → b` + `HasInhibitChanged(b)` at
  `/org/freedesktop/PowerManagement/Inhibit` (what Chromium's second inhibit
  and Firefox's third backend expect).
- Cookies are a global counter; each cookie records the caller's unique bus
  name. `UnInhibit` with an unknown cookie returns normally (hypridle
  precedent; a restarted browser replaying a stale cookie must not wedge).
  `UnInhibit` does not verify the sender (any same-uid process can already
  run code; matching hypridle).
- Watches `NameOwnerChanged`; when a cookie's owner disappears the cookie is
  reaped — a crashed browser cannot leave the session inhibited forever.
- If either well-known name cannot be acquired (another screensaver service is
  present), logs and exits 0: never fight over the name, never show a failed
  unit for a machine that has its own screensaver daemon.
- Publishes the inhibit state as JSON to
  `$XDG_RUNTIME_DIR/omarchy/idle-inhibit/state` — written with
  write-temp-then-rename so readers never see a torn file, mode 0600, on
  **every** state change including the initial "nothing inhibited" snapshot:

  ```json
  {"inhibited": false, "count": 0, "holders": []}
  ```

  `holders` entries carry `{app, reason, owner, cookie, since}` — enough for
  `omarchy debug` to say *who* is keeping the screen awake, which no
  `org.freedesktop.ScreenSaver` implementation exposes (the spec has no query
  method; that gap is a standing complaint).

The daemon never touches Wayland, never draws anything, and needs no
privileges. All decision logic lives in small pure functions so the test suite
can drive the real daemon over a real session bus.

### 2. The idle service consumes the state file

`shell/plugins/services/idle/Service.qml` gains the state-file watch it already
has a pattern for (the stay-awake indicator watcher watches a directory so
atomic renames surface as change events):

- A `FileView` on the `omarchy/idle-inhibit` directory; each change re-reads
  `state` through `IdleModel.externalInhibitFromState(raw)`, a tolerant parser
  (garbage or absence reads as "not inhibited" — a daemon crash must never
  wedge the idle timers *on*).
- `IdleMonitor.enabled` gains `&& !externalInhibit`: while any D-Bus inhibit is
  held, no idle cycle can start — the same gate `stay-awake` already uses, one
  row over.
- An inhibit arriving mid-cycle cancels it (consistent with toggling Stay
  Awake, which also cancels: starting a video should clear a screensaver that
  is already up, and Omarchy's screensaver is intrusive enough that leaving it
  over a playing video is the worse failure).
- The watcher is best-effort: missing runtime dir, unreadable file, or a
  daemon that is not running all degrade to "no external inhibits" and the
  idle timers behave exactly as they do today.
- `omarchy-shell idle status` reports the external inhibit state, and
  `omarchy-debug-idle` prints it, so a stuck inhibit is diagnosable.

### Scope and non-goals

- `xdg-desktop-portal` Inhibit (`org.freedesktop.impl.portal.Inhibit`) is not
  implemented here: flatpaked browsers go through the portal, whose Hyprland
  backend does not implement it either — that belongs to
  xdg-desktop-portal-hyprland, not to a session responder. The plan notes it
  so the gap is documented rather than rediscovered.
- `org.gnome.SessionManager` is not implemented: Firefox only reaches it after
  both freedesktop names fail, so owning the two standard names covers it.
- Power actions (suspend/hibernate inhibits via logind) are out of scope;
  Omarchy does not auto-suspend on idle.

## Edge cases the design must answer

- **Daemon starts after an inhibit was attempted**: the browser's probe failed
  once; Firefox rotates back on its next state change, Chromium on its next
  video. The unit starts with the graphical session, before browsers, so this
  is a reboot-ordering curiosity rather than a support case.
- **Daemon crashes**: the bus name drops; the state file goes stale. The
  service's tolerant parser does not treat a stale file as a held inhibit, and
  `Restart=always` brings the name back. Chromium/VLC re-probe per video.
- **Two users / two sessions**: bus names are per-session; the runtime dir is
  per-session. Nothing is shared.
- **`checkupdates`-style long holds** (a download manager inhibiting for an
  hour): that is the API working as designed; the status command exists so the
  user can see why.
- **Cookie exhaustion**: uint32 counter starting at 1; wraparound at 4 billion
  inhibits is not a support case.

## Wiring

- `default/systemd/user/omarchy-idle-inhibit.service` — house pattern
  (`After=graphical-session.target`, `WantedBy=graphical-session.target`,
  `Restart=always`, `ExecStart=/usr/bin/omarchy-idle-inhibit-daemon`; the
  PKGBUILD install line lives in omarchy-pkgs and is called out in the PR).
- New installs: added to `install/user/first-run/enable-user-units.sh`.
- Existing installs: a migration enables the unit, with the
  no-live-user-manager fallback (symlink into
  `graphical-session.target.wants`) used by the migrate-notify migration.
- No new package dependencies: `python-gobject` is already in
  `install/omarchy-base.packages`.

## Test plan

All red-green, run against the real components:

- **Daemon, over a real bus** (`dbus-run-session` + `busctl`): inhibit returns
  a cookie and flips the state file; both object paths answer; a second sender
  stacks; `UnInhibit` drops one; unknown cookie tolerated; a sender that exits
  without uninhibiting is reaped via `NameOwnerChanged`; the name-loss case
  exits 0; `HasInhibit`/`GetActive` agree with the state file; the state file
  is 0600 and always complete JSON under an inhibit/uninhibit storm; the
  initial "nothing inhibited" snapshot exists without any caller.
- **Model, in node** (`idle-test.sh`): the tolerant parser — valid state, torn
  file, garbage, missing — and the gating arithmetic.
- **Wiring, house style**: the unit file's `ExecStart`, the service's
  `FileView` and the `IdleMonitor.enabled` gate, checked the way
  `powerprofiles-set-test.sh` checks `Service.qml` bindings.
- **Migration**: idempotent rerun, respects `OMARCHY_PATH`, enables the unit
  with and without a live user manager.
- **Mutation checks**: every behavior above is proven by reverting the code
  that implements it and watching its test fail.
