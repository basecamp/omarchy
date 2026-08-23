# Settings Service API Convention

Settings becomes a first-class application, and it must not be a pile of shell commands. This document defines the stable internal capability layer between shell UI, Agent Fabric, and the underlying Omarchy/system tooling.

```text
Human UI  ──┐
            │
Agent Fabric│  (runtime, broker, permissions, ledger, undo)
            │
            ▼
Capability services / API
 ├─ window          (WindowService — first real provider)
 ├─ display
 ├─ audio
 ├─ network
 ├─ bluetooth
 ├─ power
 ├─ package management
 ├─ updates
 ├─ firmware
 ├─ themes
 ├─ input
 ├─ accounts
 ├─ recovery
 └─ …same graph as WINDOWS_7_ULTIMATE_PARITY.md
            ▼
existing Omarchy / system tooling
```

## The rule

The UI and the agent ask:

```text
setDisplayScale(displayId, 1.25)
```

not:

```text
exec("sed -i ... && hyprctl ...")
```

Pixel scraping and assembling random shell strings are not the primary agent interface. Humans and agents share this graph: same validators, state transitions, errors, rollback, and audit (`PRODUCT_DOCTRINE.md` Rule 8).

## What this buys

- validation before anything executes
- testability without a graphical session
- rollback for every consequential operation
- permissions checks in one place
- consistent, human errors (see PRODUCT_DOCTRINE.md — never `Process exited with status 1`)
- compositor flexibility behind one window capability
- **agent control through the same typed APIs** — not a later bolt-on, not raw shell access, not a chat panel that types commands

## Service contract

Each capability domain is a QML singleton under `shell/services/` (or a broker-registered provider with the same shape):

- **Readers** return structured state (typed properties or JSON), never raw command output for UI formatting.
- **Writers** are intent-named verbs (`setBrightness`, `connectWifi`, `createRestorePoint`, `minimize`) that validate first and report a structured result: `{ changed: bool, error: { title, explanation, detail } }`.
- **Operations with consequences** expose preflight information (`what will change`, estimated duration, destructive flag) so UI and agents can honor the no-bullshit installation rule before starting.
- Services own process invocation; QML components never spawn shell commands directly.
- Agent calls hit the same writers. Do not add a parallel "agent shell" path.

## What exists today

- `shell/services/WindowService.qml` is the first real capability provider: pin/unpin, minimize/restore (`omarchy-minimize` `setHidden`), snap, maximize, activate, desktops, Show Desktop, layout save/restore, per-app reopen placement. UI and `omarchy-shell window …` IPC call those verbs via `Hyprland.dispatch`.
- Writers return `{ changed, error: { title, explanation, detail } }`. IPC serializes that object (`ping` stays `"ok"`). `CapabilityBroker` catalogs window verbs, permits local-session actors, appends `capability-ledger.json`, and `undoLast` for recorded invertibles.
- Display, audio, network, bluetooth, and power still live as Superbar/heritage **panels** that run `Process` / `execDetached` / `hyprctl` / `bash -c` (see `shell/plugins/panels/`). They are not yet typed `shell/services/` domains.
- `omarchy.ultimate-settings` is a stub overlay that toggles those existing panels. It is not a Settings app.

## Placement

Domain services land in `shell/services/` as they ship (Window first; then Display, Audio, Network, Bluetooth, Power, Packages, Updates, Recovery). `WINDOWS_NATIVE_ACCEPTANCE.md` is the human smoke test. `WINDOWS_7_ULTIMATE_PARITY.md` is the job matrix. `AGENT_NATIVE_ACCEPTANCE.md` is the same-path agent matrix. Every job in those files must be satisfiable through services alone.
