# Product Doctrine — Project Ultimate

**Windows 7's desktop philosophy, rebuilt for 2026.**

Not a Windows clone. Not an Aero theme. Not "Arch for Windows users."

The objective:

> **Build the Linux desktop that a lifelong Windows user can install and immediately understand, while making the resulting experience more coherent, attractive, recoverable, customizable, private, and powerful than Windows itself.**

Underneath: Arch, Wayland, Omarchy's automation/update machinery, Quattro, Linux. On top: essentially none of Omarchy's current user-interaction doctrine survives as the default.

Omarchy's own manual says "everything in Omarchy happens via the keyboard" and that a new user initially cannot do anything with the mouse alone. That is not a UX defect in upstream Omarchy — it is what Omarchy is trying to be. This fork deliberately tries to be something else, without destroying what makes Omarchy interesting (see Mode Profiles below).

## The rules

These are non-negotiable engineering requirements, not aspirations.

### Rule 1: zero-terminal ownership

A normal user must never need a terminal to install or remove software, update or roll back, configure displays or sound, connect Wi-Fi or Bluetooth, pair peripherals, configure a printer, manage storage or format removable drives, change defaults, manage startup applications, configure input devices, connect network drives, manage users, repair common problems, install drivers/firmware, configure backups, restore the system, change themes, manage workspaces/windows, or install supported Windows applications. The terminal remains an enormously powerful application; it simply stops being a prerequisite for owning the computer.

### Rule 2: zero-hotkey-required operation

Everything must be possible with the mouse. Keyboard shortcuts are accelerators, never prerequisites. `Win+E` opening Files is great; having to know `Super+Shift+F` to discover a file manager exists is not.

### Rule 3: Windows muscle memory is an API

Treat decades of learned Windows behavior as compatibility requirements. A Windows user should intuitively expect: Start button opens applications and system places; taskbar buttons map to applications/windows with minimize/restore on clicking the active button; right-click gives contextual actions everywhere; title bar drag moves and edge/corner drag resizes; caption buttons minimize/maximize/close; double-click titlebar maximizes; Alt+Tab switches windows; Alt+F4 closes; Win+D/E/R/I/L and Win+Arrow behave as on Windows; Delete/F2/Ctrl+C/Ctrl+V work where expected. Do not teach Windows users Linux substitutes where there is no reason to.

### Rule 4: visible before memorable

A user should be able to *see* how to do something before learning a shortcut for it.

### Rule 5: progressive disclosure

The normal interface gets Settings → Display → Resolution. An expert can eventually reach Settings → System → Advanced → Configuration → open generated Hyprland configuration. The config file still exists; it stops masquerading as a Settings application.

### Rule 6: all consequential operations have state

Installing, updating, restoring, pairing, formatting, changing drivers, switching GPUs, and configuring displays must visibly communicate current state → proposed change → progress → result → recovery path. No random terminal appearing and scrolling text.

### Rule 7: recoverability is a flagship feature

Omarchy already snapshots around managed updates and supports rollback. Turn that underlying capability into something spectacular — a "restore point" normal people understand, never requiring them to know what Btrfs is.

## Naming and errors

Rename Linux concepts when the implementation detail doesn't matter — don't lie, but don't expose plumbing gratuitously. "Restore point," not "Btrfs subvolume snapshot." "Output device," not "PipeWire sink." "Network," not "NetworkManager connection profile." "Display," not "Hyprland output." Expert details remain available one disclosure level down.

Never show `Process exited with status 1` when we know what happened. Instead: **Bluetooth couldn't be turned on** — the Bluetooth service did not start — with [Try again] [Troubleshoot] [Details], where Details carries the raw service log. Every failed privileged operation states whether anything changed.

## The no-bullshit installation rule

If an action will compile an AUR package, take a while, reboot, download gigabytes, replace a driver, remove dependencies, or destroy data, tell the user beforehand. Friendly software doesn't hide consequential complexity; it translates it.

## What we copy — and refuse to copy

Windows 7 supplies the information architecture (desktop → taskbar → Start → Explorer → settings → applications); Windows 11 supplies visual restraint and polish; we supply the final design language. We do not copy Windows' ads, promoted apps, forced cloud accounts, web results hijacking local search, telemetry dark patterns, surprise restarts, or unexplained background installations. We also do not copy Linux's "just edit this file," "read the Arch Wiki," terminal-during-setup, hotkey dependence, or config syntax exposed to normal users.

## Mode Profiles

One toggle: **Desktop Mode / Power User Mode**. Power User Mode enables tiling-first layout, Omarchy's Super-key bindings, workspace-centric navigation, raw config editing, developer tooling in Start, and the original Omarchy menu. It is a profile over one underlying platform — do not build two operating systems. Profiles are defined in `default/ultimate/profiles/` and documented in `docs/mode-profiles.md`.

## Architecture

Shell UI → typed services → existing Omarchy/system mechanisms. Never QML button → random Bash string. See `docs/settings-service-api.md`.

The living roadmap against that architecture is `plans/project-ultimate.md`. Session-specific windowing proof lives in `plans/desktop-mode-handoff.md`. The forty-task gate is `WINDOWS_NATIVE_ACCEPTANCE.md`.

## Release gate

`WINDOWS_NATIVE_ACCEPTANCE.md` defines the acceptance test this product ships against.
