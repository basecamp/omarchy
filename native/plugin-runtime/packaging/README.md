# Secure runtime package

Version `0.1.0` installs side-by-side below `/usr/lib/omarchy/plugin-security/0.1.0`. It installs no command in `PATH`, systemd unit, global QML import, shell configuration, plugin, mutable state, or socket, so installation alone is inert. `package-manifest-v1.txt` is the exact relative file/mode allowlist. The configured `metadata/runtime-dependencies-v1.txt` is the exact Arch runtime dependency package set: it includes the owners of every direct worker and bridge `DT_NEEDED` entry, plus the explicitly executed Bubblewrap and Quickshell runtimes. In particular, `libxkbcommon` owns the worker's `libxkbcommon.so.0`, `systemd-libs` owns the embedded launcher's `libsystemd.so.0`, and `qt6-base` has an exact version-release pin. Package archive members and directories must be owned by `root:root`; directories use `0755`, the worker and bridge use `0755`, and QML, QML metadata, and policy data use `0644`.

The verifier syntax-checks every installed shell QML file, imports the installed native module with `ModuleProbe.qml`, and verifies its runtime invariants. Imports supplied only by the complete Omarchy shell context, including `qs.Ui`, are exercised by the live shell validation rather than resolved by this standalone package check.

The worker links `Qt6::GuiPrivate`, whose QPA ABI is not stable across Qt builds. CMake therefore reads the installed Arch `qt6-base` package version, verifies that its upstream version matches `Qt6_VERSION`, and writes (for example) `qt6-base=6.11.2-2` into the installed dependency contract. The package builder must copy every line of that contract into the package's `depends` metadata without weakening the equality constraint. This deliberately blocks a `qt6-base` update until this runtime is rebuilt and repackaged; after any `qt6-base` update, rebuild even when the upstream Qt version is unchanged and only the Arch package release changed. `verify-package.sh` rejects a stage generated for any other installed `qt6-base` build.

Configure, build, stage, and verify without system mutation:

```bash
cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-security-build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build /tmp/omarchy-plugin-security-build -j2
stage=$(mktemp -d)
sudo chown root:root "$stage"
sudo chmod 755 "$stage"
sudo env DESTDIR="$stage" cmake --install /tmp/omarchy-plugin-security-build
sudo native/plugin-runtime/packaging/verify-package.sh --staging "$stage" 0.1.0
sudo native/plugin-runtime/packaging/verify-package-test.sh "$stage" 0.1.0 /tmp/omarchy-plugin-security-build
```

Activation is an environment-scoped development overlay, not an installed default. A validation shell process receives `QML_IMPORT_PATH=/usr/lib/omarchy/plugin-security/0.1.0/qml`, `OMARCHY_PLUGIN_V2_ENABLED=1`, and `OMARCHY_PLUGIN_V2_SHELL_ENTRY=/usr/lib/omarchy/plugin-security/0.1.0/shell/SecurePluginHost.qml` before it starts the unchanged `$OMARCHY_PATH/shell` entrypoint. Removing those variables and restarting the shell deactivates the secure runtime; the ordinary Omarchy launcher remains dormant.

When activated, the singleton `PluginManager` opens only fixed trusted roots, scans activation records off the UI thread, and prepares each verified plugin in its own runtime slot. A running authenticated session remains unpublished until the host supplies exact typed readiness for the current binding and slot epoch. That boundary creates manager-owned bar, panel, and overlay rows and accepts QML attachment only for the matching opaque surface key. Failed scans retain the last good catalog, while removal or revision replacement withdraws rows and tears down endpoints before the runtime root. The production hook does not yet supply typed readiness, so the activated package starts verified runtimes but publishes no plugin surfaces.
