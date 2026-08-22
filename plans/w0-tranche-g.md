# W0 Tranche G — mouse window manager (quarters, Aero, chooser, layouts)

Worker slice after Tranche F / lock `0h`. It is not a windowing go. Keep `eddd0b57`, `9d80ecd6`, `aaf601ca`, `5942beaa`, and `a4a046b3`. Do not re-open those SHAs. Do not re-bench `4ea1dcf3` + `a5b945da`.

## Why this tranche

The leftover W0 mouse-WM gates that can move on this one-monitor QEMU guest were not Alt+Tab numbers and not hyprbars-as-pacman. They were quarters, Win+Arrow cycling, a maximize-adjacent layout chooser, drag-to-edge using **cursor** position, drag-away restore, Show Desktop, grouped taskbar peek/cycle, and a saved layout that restores the same addresses.

Window-box Aero was the wrong model: a maximized client hits every edge at once. Title-bar mouse-up was also dropped when `inputIsValid()` failed at a screen edge. Both are root causes, not extra chrome.

## What landed

- `WindowModel.snapRect` quarters (`tl`/`tr`/`bl`/`br`) with the 32px hyprbars inset
- `nextSnap` for Win+Arrow (float+up=max, left+up=tl, max+down=normal, float+down=min)
- `aeroZone(pointer, monitor)` from cursor coordinates, not the window box
- `WindowService.snapTo` / `snapArrow` / `aeroDragEnd` / `saveLayout` / `restoreLayout`
- Overlay `omarchy.ultimate-snap-chooser` (halves, maximize, quarters, save/restore)
- hyprbars `▦` button + `SUPER+Z`; drag-end spawns `omarchy-shell window aeroDragEnd 0xADDR x y`
- Taskbar grouped click cycles windows; peek lists each title with a close affordance
- Layout JSON matches by compositor address first, then appId

## Live numbers (Virtual-1 1920×1080, reserved `[0,0,0,40]`)

Not a go. GTK window is the proof.

- Halves: `0x56298351ec30` `[0,32] 960×1008`, `0x56298316a300` `[960,32] 960×1008`
- Win+Arrow left then up: `[0,32] 960×504`
- `restoreLayout` after unsnap: same two halves
- `omarchy-snap-chooser` layer `1920×1080`
- `aeroDragEnd 960 0` → fullscreen `1` `[2,34] 1916×1004`
- `aeroDragEnd 960 400` → remembered float `[208,80] 880×560` fullscreen `0`
- Show Desktop: both feet `hidden: true` on workspace `1`, then `hidden: false`
- Maps: `/usr/lib/hyprland-plugins/hyprbars.so`, `/usr/lib/hyprland-plugins/omarchy-minimize.so`

## Still open (gate stays closed)

- Alt+Tab as a reviewer-accepted held number
- Peek thumbnails / jump lists (this peek is a window list, not Aero Peek bitmaps)
- Multi-monitor, virtual desktops, parented dialogs, Steam / Wine / Electron / GTK / Qt matrix
- hyprbars as an ISO-mirror pacman package
- Tokyo Night, Nautilus, nvim-as-ordinary-text, TTY first-boot, product ISO
- A live path to install Chrome, games, or an arbitrary Windows app

## Out of scope

- Declaring W0 passed
- Phase 2–9 product work
- Putting `hyprland-plugin-hyprbars` in `install/omarchy-other.packages`
- Making foot/vim first-class
