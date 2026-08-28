# A1: Native Qt build and packaging spike

## Decision

The smallest viable native foundation is a C++20 Qt 6 executable built with CMake and Ninja. Its QML API is compiled as a versioned QML module with `qt_add_qml_module`, and the executable links Qt Core, Gui, Qml, and Quick directly. This shape supports the native-only `QQuickRenderControl` API while leaving plugin-facing QML types in an explicit module instead of registering them implicitly at startup.

The native runtime should initially ship in the existing `omarchy` Arch package. Omarchy already packages runtime executables from this repository into `/usr/bin`, and the native host, worker, and protocol must be upgraded atomically. A separate package would add cross-package compatibility and repository publication concerns without creating a security boundary. The external `omarchy-pkgs` repository remains the authoritative place to add the final build and dependency declarations.

## Executable proof

The scaffold under `experiments/plugin-security/native-build/` builds `omarchy-plugin-native-build-probe`. It proves all of the native seams required for the next build-contract node:

- a C++ Qt GUI executable can be built with the dependencies available on Omarchy;
- `QQuickRenderControl` headers and symbols are available;
- a versioned QML module can be compiled into and loaded by the executable;
- a Qt Quick scene can be instantiated without a Wayland connection by using the offscreen platform;
- the artifact installs to `/usr/bin` through standard CMake install rules; and
- the same source can be assembled as a normal Arch package with `makepkg`.

Run the development proof with:

```bash
experiments/plugin-security/native-build/run-probe
```

Build the disposable Arch package with:

```bash
cd experiments/plugin-security/native-build
makepkg --cleanbuild --force
```

The package can be inspected without installing it:

```bash
bsdtar -tf omarchy-plugin-native-build-probe-0.1.0-1-x86_64.pkg.tar.zst
```

## Dependency evidence

The probe has these build dependencies:

| Dependency | Reason | Omarchy disposition |
|------------|--------|---------------------|
| `gcc` | C++20 compiler and runtime | Existing base development toolchain; required only while building the package |
| `cmake` | Qt-supported project and install generation | Add to the package build environment, not the installed system |
| `ninja` | Deterministic CMake build executor | Add to the package build environment, not the installed system |
| `qt6-base` | Qt Core, Gui, platform integration, and development files | Add as a runtime and build dependency of `omarchy` |
| `qt6-declarative` | Qt Qml, Quick, `QQuickRenderControl`, and QML tooling | Add as a runtime and build dependency of `omarchy` |

`qt6-wayland` is not required for the headless render worker. It remains an Omarchy runtime dependency for the trusted Quickshell shell and may later be required by an explicitly granted ordinary-window worker.

The local proof was performed with Qt 6.11.2. The scaffold declares Qt 6.5 as its minimum because `QQmlApplicationEngine::loadFromModule` and the selected CMake QML workflow are available there. The production node should pin its actual minimum to the oldest Qt version in the supported Omarchy package repositories and CI images.

## Proposed production layout

The follow-on native skeleton should use one CMake project and produce narrowly separated processes:

```text
/usr/bin/omarchy-plugin-host          trusted supervisor and broker process
/usr/lib/omarchy/plugin-runtime/
  omarchy-plugin-qml-worker           sandboxed arbitrary-QML renderer
  qml/Omarchy/PluginRuntime/          worker-side QML SDK module
/usr/lib/qt6/qml/Omarchy/PluginHost/  trusted Quickshell bridge module
```

The `A3` host-module probe demonstrated that Quickshell's default import list includes `/usr/lib/qt6/qml` and dynamically loaded `Omarchy.PluginHost` from the standard URI-derived layout. The disposable-VM package test must still repeat that proof with ABI-matched Quickshell and Qt packages. The worker binary should not be placed on the ordinary user `PATH`, because it is only valid when launched with supervisor-created descriptors and sandbox state.

The executable proof compiles its QML module into its own resources. This is the least fragile arrangement for the sandbox worker: the trusted runtime SDK is immutable with the worker binary, while plugin-provided QML and assets remain a separate read-only mount. The trusted Quickshell bridge is different because Quickshell must import it dynamically; that module should be installed as a shared QML plugin.

## Packaging path

Omarchy's package definitions live in the separate `omarchy-pkgs` repository. The production implementation therefore needs coordinated changes in two repositories:

1. Add the native source tree and top-level build entry point to `omarchy`.
2. Teach the `omarchy` PKGBUILD in `omarchy-pkgs` to configure, build, test, and install the native targets.
3. Add `cmake`, `ninja`, and Qt development packages to `makedepends`; add the Qt runtime libraries that survive `namcap` and dynamic-link inspection to `depends`.
4. Install the host on `PATH`, the worker in a private libexec directory, and the trusted QML module in the Qt import tree.
5. Run the native unit tests during `check()` and exercise the installed package in the disposable graphical acceptance VM.

The experimental `PKGBUILD` demonstrates this flow without modifying the live install manifests or pretending that an experiment is a supported package.

## Measured result

The development build completed successfully on 2026-08-28 with GCC 16.2.1 and Qt 6.11.2. Running the binary with `QT_QPA_PLATFORM=offscreen`, an empty `QT_QPA_PLATFORMTHEME`, and `QT_QUICK_BACKEND=software` produced:

```text
native-build-probe: Qt 6.11.2; QQuickRenderControl linked; QML module loaded
```

`makepkg --cleanbuild --force` produced `omarchy-plugin-native-build-probe-0.1.0-1-x86_64.pkg.tar.zst` and its debug package. The main archive contains `/usr/bin/omarchy-plugin-native-build-probe`. Its direct Qt ELF dependencies are `libQt6Core.so.6`, `libQt6Gui.so.6`, `libQt6Qml.so.6`, and `libQt6Quick.so.6`; it has no `RPATH` or `RUNPATH`. Running the binary from the package staging root produced the same success marker.

This proves a locally buildable and packageable artifact, not yet installation in a clean disposable environment. The experiment includes the same smoke test in CTest and runs it from the PKGBUILD's `check()` function. `A4` should assign the eventual installed-package smoke test to the acceptance VM.

## G0 seam recommendation

Freeze these decisions at `G0`:

- CMake and C++20 are the native build contract.
- Qt Core, Gui, Qml, and Quick are the initial Qt module set.
- Host, worker, wire protocol, and trusted QML bridge ship atomically in `omarchy`.
- Worker QML SDK types compile into the worker; only the trusted Quickshell bridge is a dynamically imported native QML module.
- The worker is a private libexec artifact and cannot infer identity or authority when run directly.
- Native unit tests run through CTest; installed integration runs in the disposable VM.

The owning spikes subsequently resolved these choices:

- the trusted bridge is a dynamically imported public-API module under `/usr/lib/qt6/qml/Omarchy/PluginHost`, with final ABI-matched installed proof deferred to the disposable VM;
- the initial transport is host-created, fixed-capacity, two-slot shared memory with writable worker slots and a bounded host copy; the sealed immutable memfd test proves only the import seam;
- three private `SOCK_SEQPACKET` worker endpoints terminate at the graphical-session-scoped host daemon, and the common parser uses the 40-byte envelope frozen in `plugin-security-a2-envelope.md`; and
- final runtime library dependencies remain deferred until real render and transport code replaces this probe.
