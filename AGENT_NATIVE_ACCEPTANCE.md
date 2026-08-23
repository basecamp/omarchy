# Agent-Native Acceptance Matrix

Humans and agents share one semantic capability graph. This file is the agent-side bar. `WINDOWS_NATIVE_ACCEPTANCE.md` is the human smoke test. `WINDOWS_7_ULTIMATE_PARITY.md` is the job list those capabilities must cover.

**Identity lock:** Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability. Not Windows-like Omarchy with AI tools.

Status (tree as of 2026-08-23, metal HDMI-A-1 1920×1080 this session):

- `missing` — required fabric or rule not in the tree
- `partial` — a piece exists and is not the contract
- `present` — the row is true in code, not in aspiration

## Matrix

| # | Gate | Status | Tree notes |
|---|------|--------|------------|
| 1 | Capability graph completeness | missing | No OS-level catalog of capabilities matching the parity matrix. Typed `shell/services/` domains today: Window, AppLibrary, ModeProfile, PluginRegistry, BarWidgetRegistry. Display/audio/network/bluetooth/power are panels that exec commands. |
| 2 | Same-path human and agent operations | present (window) | Window verbs are shared: QML and `omarchy-shell window …` both call `WindowService` (IPC tags `_actor = "ipc"`). Settings/network/audio are not on that path. Agents must not grow a second "run this shell string" API. |
| 3 | No-primary-shell-string rule | partial / violated outside WindowService | WindowService dispatches Lua through `Hyprland.dispatch` (typed). Panels still `Quickshell.execDetached` / `Process` / `bash -c` / raw `hyprctl`. Notification clicks still `Util.execDetached` on persisted `omarchy-exec` strings (Download Video P0 uses this). Primary agent interface must not be pixel scraping or random shell strings. |
| 4 | Structured results | present (window) | WindowService writers return `{ changed, error: { title, explanation, detail } }`. Window IPC serializes that object. `ping` stays `"ok"`. |
| 5 | Permissions / trust | present (local-session) | `CapabilityBroker.permit` allows `ui` / `ipc` / `agent` / `undo` for catalogued window verbs and denies unknown actors/verbs. Not cloud auth. Hyprland plugin `hl.permission` is still compositor `.so` allow, not this broker. |
| 6 | Operation ledger | present (window) | Durable `~/.local/state/omarchy/ultimate/capability-ledger.json` (actor, verb, target, changed, error, undo token). Caps at 200 entries. Notification history is still toasts, not this ledger. |
| 7 | Recovery / undo | present (window invertibles) | `undoLast` replays recorded invertibles. Snap/maximize/saveLayout record `restoreNormal` / `restoreLayout`. Minimize records `restore`. Snapshot/rollback for managed updates (`omarchy-snapshot`) is separate. |
| 8 | Persistent task / event model | missing | No first-class tasks, active agents, pending actions, automations, or history objects. |
| 9 | Context broker | missing | No structured context (open windows, selection, focused app, user intent) for agents beyond what a widget can scrape. |
| 10 | Provider adapters | present (window first) | `CapabilityBroker` catalogs window verbs and dispatches to WindowService. Packages, files, devices, and settings are not plugged in yet. |
| 11 | Agent Runtime / Capability Broker | partial | Broker exists (catalog, permit, ledger, dispatch). No OS-level runtime that schedules or sandboxes agent processes. |
| 12 | Agent Center visibility in Desktop Mode | present (usage widget) | Agent Center does not exist. Desktop Mode overlay includes `omarchy.agents` in Superbar `bar.layout.right`. `TrayCluster.qml` loads registry widgets. Usage glyph stays visible with empty-state copy until Agent Center ships. Heritage `shell.json` is not rewritten. |
| 13 | `omarchy.agents` is usage, not Agent Center | present (honesty) | `shell/plugins/agents/` watches `~/.local/state/omarchy/agents/usage/` (providers, limits, cost, activity). That is one future Agent Center section, not the product. |
| 14 | Quattro plugin model preserved under Superbar | present (cluster) | Plugin registry and `bar-widget` kinds exist. Superbar notification cluster consumes `barConfig` + `BarWidgetRegistry`. Start, groups, and Show Desktop stay Windows-quality presentation, not a revert to the top Omarchy bar. |
| 15 | WindowService as first capability provider | present | Real verbs: minimize/restore (`setHidden`), snap, maximize, activate, desktops, pin, Show Desktop, reopen placement. Broker, permissions, ledger, and `{ changed, error }` are wired. |

## What must not happen

- Do not ship Agent Center UI before the fabric contract (runtime, broker, permissions, ledger, undo) is designed against WindowService.
- Do not treat a chat panel that types `hyprctl` as Agent Fabric.
- Do not hide `omarchy.agents` in Desktop Mode while "waiting for Agent Center."
- Do not add a Power User-only agents story. Agent Center is as native as Start.

## Pass bar

The OS-level pass is unchanged: a Windows-native tester and an agent can perform the same parity-matrix jobs through the same validators, see the same errors, and undo the same way — and Agent Center is a Desktop Mode surface a mouse user can find without a hotkey.

Phase 2 minimum (2026-08-23) closed rows 2, 4, 5, 6, 7, 10, 12, 14, 15 for **window**. Rows 1, 8, 9 remain missing; row 11 is broker without a sandboxed runtime. That is not the OS pass.
