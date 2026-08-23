# Windows 7 Ultimate Parity Matrix

Job completeness for Project Ultimate. Names are **jobs**, not a requirement to copy Microsoft's labels. A Windows 7 Ultimate user should recognize every row and complete it with a mouse.

This matrix is the product bar. `WINDOWS_NATIVE_ACCEPTANCE.md` is the forty-task smoke test (necessary, not sufficient; six of forty automated). `AGENT_NATIVE_ACCEPTANCE.md` is the same jobs on the agent path.

Status (tree as of 2026-08-22, no live Hyprland session on this writer host):

- `missing` — no product surface for the job
- `plumbing` — Omarchy/system machinery exists; no consumer mouse path that hides the plumbing
- `prototype` — a Desktop Mode surface exists and is not job-complete
- `present` — a usable mouse path exists for the job (still not a quality claim)

Do not mark a row `present` because a panel or hotkey exists for power users.

## Desktop jobs

| Job | Status | Tree notes |
|-----|--------|------------|
| Desktop (icons, wallpaper, context menu, Recycle) | prototype / missing | Wallpaper picker (`omarchy.image-picker`) exists. No desktop icon surface (`desktopIcons` is false). Background plugin exists. |
| Superbar (taskbar) | prototype | `omarchy.ultimate-taskbar`: Start, Task View button, running groups, Show Desktop, hard-coded `TrayCluster`. Not plugin-layout Superbar. Peek is a title list, not Aero Peek bitmaps. Group context "Close window" closes every window in the group (`TaskButton.qml`). Hard-coded charcoal/orange chrome, not the token pipeline. |
| Start | prototype | `omarchy.ultimate-start`: search, pins, app list, lock/restart/shutdown, mode toggle. Idle list hides Terminal/Vim. Not Windows 7 Start (no All Programs tree, places, jump lists, user picture, Control Panel destinations). |
| Search | prototype | Start `SearchBox` filters installed apps. Not a system Search (files, settings, control panel, history). |
| Explorer / This PC | missing as product | Files launches Nautilus (`SUPER + E` → `omarchy = "nautilus"`). Not Dolphin, not This PC. Nautilus is GTK CSD and is **not** in `hyprbars:no_bar`; two-row chrome is the expected result (not live-reverified this run). |
| Network | prototype | `omarchy.network` panel; still `Process` / `bash -c` / nmcli, not a typed Network service. |
| Personalization | plumbing / prototype | Theme packs + image picker. No Personalization Settings app. Superbar/hyprbars colors are hard-coded, so light theme cannot propagate to chrome. |
| Devices & Printers | missing | Forty-task "Add a printer" is pending. |
| Device Manager | missing | |
| Programs and Features | missing | No Software Center; no Programs and Features. |
| Default Programs | missing | Forty-task "Change the default browser" is pending. |
| User Accounts | missing | |
| Credential Manager | missing | |
| Power Options | prototype | `omarchy.power` panel. Not Power Options. Forty-task "Change power mode" is pending. |
| Sound | prototype | `omarchy.audio` panel. Forty-task volume/headphones rows pending. |
| Display | prototype | `omarchy.monitor` panel (`hyprctl keyword monitor`, `omarchy-hyprland-monitor-scaling`). Not Display Settings. |
| Firewall | plumbing | `install/config/firewall.sh` / ufw on by default (`manual/35-networking.md`). No Firewall Settings surface. |
| Update | plumbing / prototype | Heritage `omarchy.system-update` widget; Superbar does not load it. `omarchy-update` + snapshots. No Update history Settings page. Forty-task rows 28–29 pending. |
| Backup & Restore | plumbing | Snapper via `omarchy-snapshot`. No Backup and Restore UI. |
| System Restore | plumbing | Same snapshot/rollback path. No restore-point Settings. Forty-task rows 30–31 pending. |
| Disk Management | missing | |
| Task Manager | missing as product | `btop` is the Activity TUI (`manual/21-tuis.md`). Not Task Manager. |
| Resource Monitor | missing | |
| Services | missing | |
| Task Scheduler | missing | |
| Event / history | prototype (toasts only) | Notification history directory + `showHistory` replay as toasts. Not Event Viewer. Not an operation ledger. |
| Remote desktop | missing as product | |
| Drive encryption | missing as product | |
| Sharing | missing as product | Forty-task SMB row pending. |
| Language / locale | prototype | Heritage `omarchy.keyboard-layout`; Superbar cluster does not load it. Forty-task "Change keyboard layout" pending. |
| Accessibility | missing as product | Reduced motion called out in tokens; no Accessibility Settings. |
| File associations | missing as product | |
| Properties | missing as product | |
| Context menus | prototype | Taskbar/Start/peek menus exist. Not "right-click everywhere" as the Windows API. |

## 2026 layers

| Job | Status | Tree notes |
|-----|--------|------------|
| Software Center | missing | Phase 7 in the plan. Pacman/AUR/Flatpak are CLI/menu today. |
| Compatibility Center | missing | Phase 8. No "install one known-compatible .exe" path. |
| Snapshot recovery | plumbing | `omarchy-snapshot`, Limine snapper restore. Consumer "restore point" UI missing. |
| Modern display (scaling, HDR, night light) | prototype / plumbing | Monitor panel + `omarchy.nightlight` service. Forty-task scaling and night light pending. |
| Proton / gaming | missing | Steam install is forty-task pending; no Gaming / Proton surface. |
| Privacy | missing | Doctrine refuses telemetry; no Privacy Settings. |
| Agent Fabric | missing | See `AGENT_NATIVE_ACCEPTANCE.md`. WindowService exists; fabric does not. |
| Agent Center | missing | `omarchy.agents` is a usage/limits bar-widget, not Agent Center. Superbar does not load it. |

## Caption / windowing (not a substitute for the jobs above)

W0 is an architecture GO (Hyprland stays). Remaining product-windowing debt is recorded in `plans/project-ultimate.md`. Do not treat this matrix as green because snap and Alt+Tab IPC work.
