# Product Doctrine — Project Ultimate

## Identity (locked)

**Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability.**

**Not:** Windows-like Omarchy with AI tools.

Not a Windows clone. Not an Aero theme. Not "Arch for Windows users." Not a nicer Omarchy with a taskbar and a chat panel.

The objective:

> **Build the Linux desktop that a lifelong Windows user can install and immediately understand, while making the resulting experience more coherent, attractive, recoverable, customizable, private, and powerful than Windows itself — and make every meaningful capability callable by an agent on the same path a human uses.**

Underneath: Arch, Wayland, Omarchy's automation/update machinery, Quattro, Linux. On top: essentially none of Omarchy's current user-interaction doctrine survives as the default.

Omarchy's own manual says "everything in Omarchy happens via the keyboard" and that a new user initially cannot do anything with the mouse alone. That is not a UX defect in upstream Omarchy — it is what Omarchy is trying to be. This fork deliberately tries to be something else, without destroying what makes Omarchy interesting (see Mode Profiles below).

This product is still **REJECTED** as an OS. Windowing Gate W0 is an **architecture GO** (Hyprland stays). It is not a finished Windows 7 window manager and not a shippable desktop. Progress against the locked identity is roughly **15–20%**: Phase 0 is mostly in the repo; W0 architecture passed; phases after W0 are not product-complete. Do not declare victory after a shiny taskbar.

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

### Rule 8: agent-native (same capability graph)

Every meaningful human-desktop capability must have a structured, agent-callable equivalent. Pixel scraping and random shell strings are not the primary agent interface. Humans and agents share one semantic capability graph: the same validators, state transitions, errors, rollback, and audit.

The agent UI can wait. The agent architecture cannot. Agent Fabric (runtime, capability broker, provider adapters, permissions/trust, context broker, persistent task/event model, operation ledger, recovery/undo) is a core gate before Phase 2/3 UI sprawl. `WindowService` is the first real capability provider in the tree; other domains still live as panel QML that execs commands.

Agent Center belongs in Desktop Mode as native as Start — not buried in Power User Mode. Today's `omarchy.agents` usage widget (providers, limits, cost, activity) is one section of that surface, not the product. Until Agent Center exists, `omarchy.agents` must remain visible in Desktop Mode Superbar chrome. The Superbar must keep Quattro's plugin model under Windows-quality presentation; a hard-coded widget list is not the end state.

## Naming and errors

Rename Linux concepts when the implementation detail doesn't matter — don't lie, but don't expose plumbing gratuitously. "Restore point," not "Btrfs subvolume snapshot." "Output device," not "PipeWire sink." "Network," not "NetworkManager connection profile." "Display," not "Hyprland output." Expert details remain available one disclosure level down.

Never show `Process exited with status 1` when we know what happened. Instead: **Bluetooth couldn't be turned on** — the Bluetooth service did not start — with [Try again] [Troubleshoot] [Details], where Details carries the raw service log. Every failed privileged operation states whether anything changed.

## The no-bullshit installation rule

If an action will compile an AUR package, take a while, reboot, download gigabytes, replace a driver, remove dependencies, or destroy data, tell the user beforehand. Friendly software doesn't hide consequential complexity; it translates it.

## What we copy — and refuse to copy

Windows 7 Ultimate supplies the complete, obvious desktop model (desktop → Superbar → Start → Explorer → settings → applications); Windows 11 supplies visual restraint and polish; we supply the final design language. We do not copy Windows' ads, promoted apps, forced cloud accounts, web results hijacking local search, telemetry dark patterns, surprise restarts, or unexplained background installations. We also do not copy Linux's "just edit this file," "read the Arch Wiki," terminal-during-setup, hotkey dependence, or config syntax exposed to normal users.

"Not a clone" is that refusal of ads, telemetry, and forced accounts. It is not permission to ship a Linux developer box as the default product. Every normal Windows job still has to work with a mouse: install apps, Chrome, files, games, settings, printers, Wi-Fi. The terminal stays a powerful application. It is not how you own the machine.

## Mode Profiles

One toggle: **Desktop Mode / Power User Mode**. Power User Mode enables tiling-first layout, Omarchy's Super-key bindings, workspace-centric navigation, raw config editing, developer tooling in Start, and the original Omarchy menu. It is a profile over one underlying platform — do not build two operating systems. Profiles are defined in `default/ultimate/profiles/` and documented in `docs/mode-profiles.md`.

**Overlay rule:** Desktop Mode must not rewrite `~/.config/omarchy/shell.json`. `shell.qml` computes an effective config (taskbar id and bottom position). Plugin enable/disable and Settings still persist the on-disk file.

Profile feature flags mean **capability exists in this profile**, not "we intend to build it." Unimplemented surfaces stay `false`.

## Architecture

**UI → typed service → existing Omarchy/system tooling.** Never QML button → random Bash string. See `docs/settings-service-api.md`.

Agent Fabric sits on that same graph: an OS-level Agent Runtime and Capability Broker dispatch the same typed verbs humans use. Provider adapters wrap compositor, settings, packages, files, and devices. Permissions and trust are checked in one place. Every consequential operation writes an operation ledger and exposes recovery/undo. WindowService is the first provider; it is not the whole fabric.

The living roadmap is `plans/project-ultimate.md`. Session-specific windowing proof lives in `plans/desktop-mode-handoff.md`.

## Acceptance (three gates)

The forty-task file `WINDOWS_NATIVE_ACCEPTANCE.md` is the smoke test: can a Windows person use this PC without a terminal or the web? It is **necessary and not sufficient**. Only six of forty rows are automated (pin, unpin, minimize three, restore one, snap two, Alt+Tab). A green subset does not ship the OS.

Job completeness is `WINDOWS_7_ULTIMATE_PARITY.md` (Windows 7 Ultimate jobs plus 2026 layers). Agent-callable completeness is `AGENT_NATIVE_ACCEPTANCE.md`. Release requires all three, plus the power-user second test in the forty-task file.

## Release gate

Do not merge `work` into `main` as the OS. Do not call a product ISO a go from doctrine, from W0, or from a Superbar screenshot.
