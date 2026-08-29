# Secure runtime staging contract

The initial package is dormant and side-by-side. Version `0.1.0` owns only `/usr/lib/omarchy/plugin-security/0.1.0`; it installs no global command, systemd unit, shell file, migration, user configuration, plugin, state, or socket. `package-manifest-v1.txt` is the exact relative file/mode allowlist, and `runtime-dependencies-v1.txt` is the exact direct runtime package list. Package archive members and directories must be owned by `root:root`; directories use `0755`, the worker and bridge use `0755`, and QML, QML metadata, and policy data use `0644`.

Configure, build, stage, and verify without system mutation:

```bash
cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-security-build -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build /tmp/omarchy-plugin-security-build -j2
stage=$(mktemp -d)
DESTDIR="$stage" cmake --install /tmp/omarchy-plugin-security-build --prefix /usr
native/plugin-runtime/packaging/verify-package.sh --staging "$stage" 0.1.0
native/plugin-runtime/packaging/verify-package-test.sh "$stage" 0.1.0
```

Activation is an environment-scoped development overlay, never an installed default. A validation shell process receives `QML_IMPORT_PATH=/usr/lib/omarchy/plugin-security/0.1.0/qml`, `OMARCHY_PLUGIN_V2_ENABLED=1`, and `OMARCHY_PLUGIN_V2_SHELL_ENTRY=/usr/lib/omarchy/plugin-security/0.1.0/shell/SecurePluginHost.qml` before it starts the unchanged `$OMARCHY_PATH/shell` entrypoint. Removing those three variables and restarting the shell deactivates v2. The ordinary Omarchy launcher remains unchanged, so the next normal launch is dormant.

Install and uninstall must be performed by the eventual repository-native package. Its uninstall owns only the exact versioned root and is therefore idempotent through the package manager: if the package is absent, cleanup succeeds without touching v1 plugins or Omarchy files. A staging cleanup removes only the path returned by that invocation's `mktemp -d`. Before live validation, record package ownership and SHA-256 for `$OMARCHY_PATH/shell`, user shell configuration, the v1 plugin root, and the prospective v2 root; repeat the same snapshot after deactivation and package removal.

Do not activate this package yet. The native in-process host backend and installed-style Quickshell acceptance test are still incomplete, so the current bridge intentionally publishes no surfaces.
