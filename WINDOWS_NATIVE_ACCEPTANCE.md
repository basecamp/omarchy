# Windows-Native Acceptance Manifest

Smoke test: can a Windows person use this PC? Give a Windows-native tester a completely clean machine. Do not give them documentation. Ask them to complete all forty tasks below.

This file is **necessary and not sufficient**. Job completeness is `WINDOWS_7_ULTIMATE_PARITY.md`. Agent-callable completeness is `AGENT_NATIVE_ACCEPTANCE.md`. A green Superbar and six numbered windowing rows do not ship the OS.

Release still requires: **they complete all forty without opening Terminal and without searching the web.**

Anything that requires documentation is a UX defect to investigate. Anything that requires the terminal is a missing product surface. Anything that requires memorizing a hotkey is a missing affordance.

Only **six of the forty numbered rows** are automated (20–25). The other numbered rows are `pending`. That is not the whole harness: after the numbered loop, `test/acceptance.d/windows-native-test.sh` still runs unnumbered proofs (maximize, hyprbars/omarchy-minimize maps from `/usr/lib/hyprland-plugins`, overlay chrome gone, Show Desktop, virtual desktops, Task View, fullscreen, multi-monitor, toolkit, pointer). Do not say only six tests exist.

Status legend: `pending` (no automated coverage yet), `manual` (human-tested only), `automated` (covered by `test/acceptance.d/windows-native-test.sh` or another harness entry).

| # | Task | Status |
|---|------|--------|
| 1 | Install the OS | pending |
| 2 | Connect Wi-Fi | pending |
| 3 | Set display scaling to 125% | pending |
| 4 | Change the wallpaper | pending |
| 5 | Pair Bluetooth headphones | pending |
| 6 | Adjust output volume | pending |
| 7 | Install Firefox or Chrome | pending |
| 8 | Install Steam | pending |
| 9 | Open Downloads | pending |
| 10 | Create a folder | pending |
| 11 | Rename it | pending |
| 12 | Copy files | pending |
| 13 | Zip them | pending |
| 14 | Connect a USB drive | pending |
| 15 | Eject it | pending |
| 16 | Connect to an SMB share | pending |
| 17 | Open a PDF | pending |
| 18 | Edit a text file | pending |
| 19 | Change the default browser | pending |
| 20 | Pin an app | automated |
| 21 | Unpin an app | automated |
| 22 | Minimize three windows | automated |
| 23 | Restore the one they want | automated |
| 24 | Snap two windows | automated |
| 25 | Use Alt+Tab | automated |
| 26 | Find an application that is consuming CPU | pending |
| 27 | Disable a startup application | pending |
| 28 | Install system updates | pending |
| 29 | Inspect update history | pending |
| 30 | Create a restore point | pending |
| 31 | Roll back a deliberately broken update | pending |
| 32 | Add a printer | pending |
| 33 | Change keyboard layout | pending |
| 34 | Enable night light | pending |
| 35 | Change power mode | pending |
| 36 | Install one known-compatible `.exe` | pending |
| 37 | Uninstall it | pending |
| 38 | Find system/storage information | pending |
| 39 | Troubleshoot intentionally broken audio | pending |
| 40 | Shut down | pending |

## Second test

Give the same machine to an Omarchy/Arch power user. They should still be able to open a terminal, use supported pacman-equivalent tooling, enable original Omarchy bindings, turn on tiling, use workspaces aggressively, edit configs, script the system, install plugins, and customize everything. Consumer usability doesn't require crippling Linux.

## Harness

`test/acceptance.d/windows-native-test.sh` is the executable skeleton for this manifest inside the disposable-VM acceptance suite (see `agents/skills/acceptance-tests.md`). Numbered rows 1–40 map to named cases in the loop (`skip_task` for pending). After that loop the same file still proves maximize, plugin maps, overlay-chrome absence, Show Desktop, virtual desktops, Task View, fullscreen, multi-monitor, toolkit snap, and the absolute-pointer helper.

A green harness that only talks to `omarchy-shell window` and checks `left.x <= right.x` does not pass the OS. The extra proofs were sufficient as architecture evidence for Windowing Gate W0 on Hyprland, and (with three-button SSD, Files CSD, reopen memory, and pointer hover) as **agent-reported** product-windowing evidence. They are not Windows 7 Ultimate.

Desktop shell acceptance is **FAIL** until Start click-through is proven (outside-click and orb re-toggle landed in `e3bf9385`; the overlay still swallows the click). See `HANDOFF_NEW_BOX_2026-08-23.md`.