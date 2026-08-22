# Settings Service API Convention

Settings becomes a first-class application, and it must not be a pile of shell commands. This document defines the stable internal capability layer between shell UI and the underlying Omarchy/system tooling.

```text
UI
 ↓
Settings service/API
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
 └─ recovery
       ↓
existing Omarchy / system tooling
```

## The rule

The UI asks:

```text
setDisplayScale(displayId, 1.25)
```

not:

```text
exec("sed -i ... && hyprctl ...")
```

## What this buys

- validation before anything executes
- testability without a graphical session
- rollback for every consequential operation
- permissions checks in one place
- consistent, human errors (see PRODUCT_DOCTRINE.md — never `Process exited with status 1`)
- future compositor flexibility
- eventual AI control through the same typed APIs instead of raw shell access

## Service contract

Each capability domain is a QML singleton under `shell/services/` with the same shape:

- **Readers** return structured state (typed properties or JSON), never raw command output for UI formatting.
- **Writers** are intent-named verbs (`setBrightness`, `connectWifi`, `createRestorePoint`) that validate first and report a structured result: `{ changed: bool, error: { title, explanation, detail } }`.
- **Operations with consequences** expose preflight information (`what will change`, estimated duration, destructive flag) so UI can honor the no-bullshit installation rule before starting.
- Services own process invocation; QML components never spawn shell commands directly.

## Placement

Domain services land in `shell/services/` as they ship (Display, Audio, Network, Bluetooth, Power, Packages, Updates, Recovery). The acceptance manifest in `WINDOWS_NATIVE_ACCEPTANCE.md` is the checklist of domains that must exist before release; every task there must be satisfiable through services alone.
