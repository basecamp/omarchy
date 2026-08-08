# Visual Verification

Read this before finishing any change with a visual effect: Omarchy shell
styling and layout, panels, menus, notifications, desktop appearance,
animations, transitions, screenshots, and screen recording flows.

Visual changes must be verified in the running UI in addition to automated
tests. Creating an artifact is not sufficient: inspect it for clipping,
overlap, incorrect spacing, stale state, focus problems, and visual
regressions before finishing.

Take a full-screen screenshot without opening the editor:

```bash
omarchy capture screenshot fullscreen save
```

The command prints the saved path and writes to the configured Pictures
directory. Use `omarchy screenshot` for the interactive smart-region flow.
Capture reference and candidate states as separate images when changing a
layer-shell surface or layout, then compare both.

Record a short full-screen video for animation, transition, timing, capture, or
screen-recording changes:

```bash
omarchy screenrecord --fullscreen
# Exercise the changed behavior.
omarchy screenrecord --stop-recording
```

The stop command prints the saved video path in the configured Videos
directory. Review the recording before finishing, and keep it short and focused
on the changed behavior.

For interactive UI work, use `wtype` to simulate keyboard input when available.
Example: start the UI in the background, wait briefly for focus, then run
`wtype -k Right -k Return` to exercise keyboard selection and confirm the
resulting command output or state change. Prefer this over manual-only
verification when a UI returns a selected value or changes a symlink/config.

If a launched UI would otherwise remain open, keep track of its PID and stop it
after the screenshot or recording; avoid broad process kills unless checking
with `ps` first.
