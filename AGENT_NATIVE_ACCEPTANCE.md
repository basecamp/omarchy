# Agent-Native Acceptance Matrix

Humans and agents share one semantic capability graph. This file is the agent-side bar. `WINDOWS_NATIVE_ACCEPTANCE.md` is the human smoke test. `WINDOWS_7_ULTIMATE_PARITY.md` is the job list those capabilities must cover.

**Identity lock:** Windows 7 Ultimate's complete, obvious, mouse-native desktop model rebuilt for 2026, with an agent-native operating fabric underneath every system capability. Not Windows-like Omarchy with AI tools.

Status (tree as of 2026-08-22):

- `missing` — required fabric or rule not in the tree
- `partial` — a piece exists and is not the contract
- `present` — the row is true in code, not in aspiration

## Matrix

| # | Gate | Status | Tree notes |
|---|------|--------|------------|
| 1 | Capability graph completeness | missing | No OS-level catalog of capabilities matching the parity matrix. Typed `shell/services/` domains today: Window, AppLibrary, ModeProfile, PluginRegistry, BarWidgetRegistry. Display/audio/network/bluetooth/power are panels that exec commands. |
| 2 | Same-path human and agent operations | partial | Window verbs are shared: QML and `omarchy-shell window …` both call `WindowService`. That is the pattern. Settings/network/audio are not on that path. Agents must not grow a second "run this shell string" API. |
| 3 | No-primary-shell-string rule | partial / violated outside WindowService | WindowService dispatches Lua through `Hyprland.dispatch` (typed). Panels still `Quickshell.execDetached` / `Process` / `bash -c` / raw `hyprctl`. Primary agent interface must not be pixel scraping or random shell strings. |
| 4 | Structured results | partial | Doctrine wants `{ changed, error: { title, explanation, detail } }`. Window IPC returns `"ok"`. |
| 5 | Permissions / trust | missing | No Agent Fabric permission broker. Hyprland plugin `hl.permission` for `.so` load is compositor plugin allow, not user/agent trust. |
| 6 | Operation ledger | missing | No durable ledger of agent/human capability calls. Notification history is toasts, not an audit of operations. |
| 7 | Recovery / undo | missing as fabric | Snapshot/rollback exists for managed updates (`omarchy-snapshot`). Window `restoreNormal` / `restoreLayout` are windowing, not a general undo. |
| 8 | Persistent task / event model | missing | No first-class tasks, active agents, pending actions, automations, or history objects. |
| 9 | Context broker | missing | No structured context (open windows, selection, focused app, user intent) for agents beyond what a widget can scrape. |
| 10 | Provider adapters | missing as fabric | WindowService is the first provider. No adapter interface that packages, files, devices, and settings plug into. |
| 11 | Agent Runtime / Capability Broker | missing | No OS-level runtime that schedules, sandboxes, and dispatches capability calls. |
| 12 | Agent Center visibility in Desktop Mode | missing (regression vs heritage bar) | Agent Center does not exist. Heritage `config/omarchy/shell.json` includes `omarchy.agents`. Desktop Mode overlays `omarchy.ultimate-taskbar`, whose `TrayCluster.qml` hard-codes audio/bluetooth/network/monitor/power + tray + clock and **omits** `omarchy.agents`. Usage widget must stay visible until Agent Center ships. |
| 13 | `omarchy.agents` is usage, not Agent Center | present (honesty) | `shell/plugins/agents/` watches `~/.local/state/omarchy/agents/usage/` (providers, limits, cost, activity). That is one future Agent Center section, not the product. |
| 14 | Quattro plugin model preserved under Superbar | partial | Plugin registry and `bar-widget` kinds exist. Superbar does not use them for its cluster. Hard-coded widget list is not the end state. |
| 15 | WindowService as first capability provider | partial | Real verbs: minimize/restore (`setHidden`), snap, maximize, activate, desktops, pin, Show Desktop. Not a broker, not permissions, not ledger. |

## What must not happen

- Do not ship Agent Center UI before the fabric contract (runtime, broker, permissions, ledger, undo) is designed against WindowService.
- Do not treat a chat panel that types `hyprctl` as Agent Fabric.
- Do not hide `omarchy.agents` in Desktop Mode while "waiting for Agent Center."
- Do not add a Power User-only agents story. Agent Center is as native as Start.

## Pass bar

This matrix passes when a Windows-native tester and an agent can perform the same parity-matrix jobs through the same validators, see the same errors, and undo the same way — and when Agent Center is a Desktop Mode surface a mouse user can find without a hotkey.
