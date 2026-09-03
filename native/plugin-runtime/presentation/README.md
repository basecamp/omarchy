# Secure worker presentation SDK

`Omarchy.PluginPresentation 1.0` is a pure-QML compatibility module embedded in the versioned schema-v2 worker. It exists to keep ordinary plugin presentation code familiar without importing Omarchy's trusted shell implementation into the sandbox.

The module currently provides authority-free theme and sizing defaults, controls used by existing Omarchy plugins, packaged-text reads, a private-storage wrapper, and a Process-shaped asynchronous broker-call base. `BrokerProcess`, `PrivateStorage`, and `PackagedText` call only the worker's manifest-bound `runtime` API; they cannot widen a manifest request or bypass broker authorization. All other module types are presentation-only.

This module is not `qs.Commons` or `qs.Ui`. Those URIs identify private modules in the trusted shell and may contain ambient host integrations. A schema-v2 plugin must import `Omarchy.PluginPresentation` explicitly so review can distinguish sandbox compatibility from trusted shell access.

The worker currently certifies `QtQml`, `QtQuick`, Basic-style `QtQuick.Controls`, `QtQuick.Effects`, `QtQuick.Layouts`, and `QtQuick.Shapes`. Effects and Layouts are each mounted as an exact three-file native module closure. Controls uses five exact read-only plugin/metadata triplets for Controls, Templates, the shared Controls implementation, Basic, and the Basic implementation. Representative types are preloaded before the steady-state syscall filter, the style is pinned to Basic, and runtime-created controls resolve from the same trusted resource namespaces. No alternate style, `QtQuick.Dialogs`, or platform-dialog module is mounted. Controls `Dialog` and `Popup` remain offscreen in-scene presentation types.

The worker does not expose native Quickshell registrations, `Quickshell.Io`, `Quickshell.Hyprland`, `Quickshell.Wayland`, host D-Bus, shell IPC, host filesystem paths, or arbitrary host process execution. A separately implemented, pure-QML `Quickshell`/`Quickshell.Widgets` compatibility subset supplies only authority-free scene composition and presentation helpers. Further APIs may be added only after their resources, dependencies, descriptors, syscalls, and behavior without host sockets have been threat-modeled and tested.

Plugin-local adapters should use product-specific names. For example, a Radio adapter translating legacy command arrays into `network.fetch` and `media.play-stream` calls is a `RadioProcess`, not a shared `Process`. A shared type belongs here only when its behavior is reusable and its authority is no greater than direct access to the existing worker API.

Deferred compatibility work includes a declared sandbox-local helper runner, lifecycle convenience types, richer input helpers, theme projection from bounded host-owned state, and a reviewed classification of Quickshell modules. None of those should be emulated with access to the trusted host shell.

Quickshell's native surface types are an intentional migration boundary rather than deferred presentation wrappers. See [QUICKSHELL_SURFACES.md](QUICKSHELL_SURFACES.md) for why `PanelWindow`, `PopupWindow`, `Region` window masks, and Wayland attached properties cannot honestly map to worker Items while the host retains native-window and compositor authority.
