# Omarchy secure plugin runtime

This directory builds the dormant schema-v2 security layer for the existing Omarchy Quickshell. The worker runs arbitrary plugin QML and declared sidecars inside Bubblewrap, renders through `QQuickRenderControl`, and has no Wayland, X11, or session-bus connection. The `Omarchy.PluginHost` native QML module carries authenticated frames and input; package-owned QML wraps those items in shell-owned bar, panel, and overlay surfaces. There is no standalone product window host.

Schema v1 remains the pre-security QML loader and is trusted by default. It is unsandboxed and outside the secure runtime's guarantees. Schema v2 has a separate import namespace, versioned installation/state roots, authenticated IPC identity, explicit feature gate, and no rejection fallback to schema v1.

Schema-v2 QML requests an external effect with `runtime.invoke(capability, operation, arguments)`, for example `runtime.invoke("storage.private", "write", { key: "state", value: bytes })`. Structured CLI requests use the explicit `runtime.execute("bash", command, arguments)` boundary. The `bash` runner selects the manifest-bound `bash.execute/run` authority namespace; it does not invoke a shell, accept command text, or allow QML to choose a host path, environment, or provider profile. The worker accepts only an exact capability and operation pair allowed by that plugin revision's manifest request: built-in requests name a capability and inherit its registered operation set, while extensible requests name their operations explicitly. For an extensible capability, the worker also copies the manifest's trusted definition generation and digest into the broker envelope; the plugin cannot select or replace that authority reference. The broker still independently verifies the active grant, scope, provider, and definition before dispatch. `runtime.permissions`, `runtime.hasPermission(capability, operation)`, and `runtime.permissionState(capability, operation)` let QML hide or degrade optional features, but never authorize an effect.

Schema-v2 plugins may import `Omarchy.PluginPresentation 1.0`. This pure-QML compatibility SDK is embedded in the versioned worker and supplies authority-free controls, sizing/theme defaults, packaged-text and private-storage helpers, and a reusable asynchronous broker-call lifecycle. The SDK does not wrap command execution or import the trusted shell's private `qs.Commons` or `qs.Ui` modules. It exposes no host Quickshell runtime, compositor objects, host processes, host files, D-Bus, shell IPC, or network access. Authority-bearing work remains visibly rooted at the manifest-declared `runtime` object.

Plugin-owned Qt Quick, JavaScript, assets, and pure-QML modules remain inside the worker boundary. The current certified native-QML set is deliberately smaller than unrestricted Quickshell: `QtQml`, `QtQuick`, `QtQuick.Controls` with the Basic style, `QtQuick.Effects`, `QtQuick.Layouts`, and `QtQuick.Shapes`. Effects and Layouts are exact three-file presentation-only closures. Controls adds five exact read-only binary/metadata triplets: Controls, Templates, Controls implementation, Basic style, and Basic implementation. The worker pins `QT_QUICK_CONTROLS_STYLE=Basic`, preloads representative controls before steady-state seccomp, and admits only those compiled resource namespaces. Other styles, `QtQuick.Dialogs`, platform integrations, and host theme discovery remain absent. The in-scene Controls `Dialog` and `Popup` types are presentation objects rendered by the worker's offscreen platform; they are not `QtQuick.Dialogs` or native platform dialogs.

These presentation modules add no descriptor, syscall, process, filesystem, network, D-Bus, compositor, or shell-IPC authority. Adding another Quickshell or Qt module requires the same explicit resource/mount/syscall threat review and adversarial loading tests. In particular, sandbox-local execution of declared plugin helpers is distinct from exposing Quickshell's ambient `Process` API and remains deferred until the executable identity, startup timing, descendants, cancellation, and steady-state seccomp contracts are proven.

Native Quickshell surfaces are not compatibility presentation types. `PanelWindow`, `PopupWindow`, their `Region` masks, and `Quickshell.Wayland` policy objects control distinct native windows and compositor behavior, so the worker does not provide inert Item-shaped facades for them. Schema-v2 manifests and the trusted host own surface placement and lifecycle; entry-root `inputRegions` and surface intents cover the bounded worker side. The exact compatibility decision is recorded in `presentation/QUICKSHELL_SURFACES.md`.

The worker does not provide modules under the standard `Quickshell` URI. The installed Quickshell cannot currently be embedded with restricted providers or a remote surface backend, and a small facade did not materially reduce a representative secure port. Plugins therefore explicitly migrate authority-bearing calls to `runtime` and use ordinary plugin-owned Qt Quick/QML for presentation. `QUICKSHELL_SANDBOX_RUNTIME.md` records how future upstream provider interfaces could reduce those migrations without becoming a product dependency.

The same-UID Quickshell IPC socket is trusted session control and must remain outside the v2 worker sandbox. The permission CLI's `interactive_cli` actor records ingress provenance, not proof that a human approved the change; its TTY prompts are an ergonomic confirmation.

Installation is side-by-side below `/usr/lib/omarchy/plugin-security/${PROJECT_VERSION}`. It installs no command in `PATH`, no systemd unit, no global QML import, and no shell configuration. Activation requires `OMARCHY_PLUGIN_V2_ENABLED=1`, `OMARCHY_PLUGIN_V2_SHELL_ENTRY` pointing to the package-owned `SecurePluginHost.qml`, and the versioned `qml` directory on Quickshell's import path. Without all three, installation is inert.

Build and test locally:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
stage=$(mktemp -d)
sudo chown root:root "$stage"
sudo chmod 755 "$stage"
sudo env DESTDIR="$stage" cmake --install build/plugin-runtime
```

Packagers may set `OMARCHY_PLUGIN_QT_MIN_VERSION`. The `/usr` prefix and versioned `/usr/lib/omarchy/plugin-security` package root are fixed; use only `DESTDIR` for staging. Building and installing the artifacts does not activate schema v2.

`packaging/arch/build-package.sh` builds the inert Arch package from the committed runtime tree. `packaging/arch/test-package-reproducibility.sh` proves two clean builds have identical installed payloads, `.PKGINFO`, and normalized build metadata after ignoring only the `.BUILDINFO` build and start directories and their corresponding `.MTREE` entry. Those makepkg context paths intentionally keep the outer archives from being byte-identical.
