# User systemd units

Read this before writing or enabling anything under `~/.config/systemd/user/`,
turning on linger (`loginctl enable-linger`), or installing a timer that
should run at login or while nobody is at the desk.

UWSM owns `graphical-session.target`. Omarchy's shipped user units under
`$OMARCHY_PATH/default/systemd/user/` start *with* that target via
`WantedBy=graphical-session.target`. They never `Requires=` or `Wants=` it.

Copy that pattern. Generic systemd examples for GUI services often use
`Requires=graphical-session.target`. That *starts* the target. If the user
manager is already up (linger, a Persistent timer, an SSH login), UWSM then
sees a session already active, prints
`A compositor or graphical-session* target is already active!`, and refuses
to start Hyprland. Plymouth has quit. The screens stay black until the next
boot.

## Session-bound daemons

Need a display, should die with the compositor. Match shipped units
(`omarchy-fcitx5.service`, `omarchy-crash-watch.service`):

```
[Unit]
After=graphical-session.target
PartOf=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY

[Install]
WantedBy=graphical-session.target
```

`After=` is ordering only. `ConditionEnvironment=WAYLAND_DISPLAY` is what
stops the unit starting from a linger user manager with no compositor.
Do not `Requires=` or `Wants=` `graphical-session.target`.

## After the desktop starts

Prefer `omarchy hook install post-boot <script>` ([`hooks.md`](hooks.md)).
Do not pull `graphical-session.target` from a systemd unit to get the same
effect.

## Headless jobs

Timers and services that need no display must not mention
`graphical-session.target` at all. Do not enable linger unless the job
must run with no one logged in.

After editing units: `systemctl --user daemon-reload`. Then
`systemctl --user show graphical-session.target -p RequiredBy` must not
list the job.
