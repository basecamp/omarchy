# Omarchy secure plugin runtime

This directory builds the dormant schema-v2 security layer for the existing Omarchy Quickshell. The worker runs arbitrary plugin QML and declared sidecars inside Bubblewrap, renders through `QQuickRenderControl`, and has no Wayland, X11, or session-bus connection. The `Omarchy.PluginHost` native QML module carries authenticated frames and input; package-owned QML wraps those items in shell-owned bar, panel, and overlay surfaces. There is no standalone product window host.

Schema v1 remains the legacy unsandboxed QML loader. Schema v2 has a separate import namespace, versioned installation/state roots, authenticated IPC identity, explicit feature gate, and no rejection fallback to v1.

Installation is side-by-side below `${CMAKE_INSTALL_LIBDIR}/omarchy/plugin-security/${PROJECT_VERSION}`. It installs no command in `PATH`, no systemd unit, no global QML import, and no shell configuration. Activation requires `OMARCHY_PLUGIN_V2_ENABLED=1`, `OMARCHY_PLUGIN_V2_SHELL_ENTRY` pointing to the package-owned `SecurePluginHost.qml`, and the versioned `qml` directory on Quickshell's import path. Without all three, installation is inert.

Build and test locally:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
cmake --install build/plugin-runtime --prefix "$(mktemp -d)"
```

Packagers may set `OMARCHY_PLUGIN_QT_MIN_VERSION` and `OMARCHY_PLUGIN_INSTALL_ROOT`. Building and installing the artifacts does not activate schema v2.
