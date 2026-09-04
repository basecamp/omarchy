# Secure runtime package

Version `0.1.0` installs side-by-side below `/usr/lib/omarchy/plugin-security/0.1.0`. It installs no command in `PATH`, systemd unit, global QML import, shell configuration, plugin, mutable state, running provider process, or socket, so installation alone is inert. The packaged command executor stays dormant until a granted plugin invokes it. Its sole packaged vocabulary is the reviewed `github-api-v1` argv grammar; installation does not grant that permission or start `gh`, and a missing system `gh` fails the call closed. `package-manifest-v1.txt` is the exact relative file/mode allowlist. Generic trusted definitions are generated into the versioned `capabilities.d` root; they grant nothing without review and an exact trusted provider. `metadata/capability-catalog-v1.json` exposes their generated generation and digest pins for manifest tooling without weakening the requirement that manifests carry those exact values. The committed `metadata/runtime-dependencies-v1.txt` is the exact Arch runtime dependency package set: it includes Omarchy, the owners of every direct worker and bridge `DT_NEEDED` entry, and the explicitly executed Bubblewrap and Quickshell runtimes. The Qt packages are ordinary unversioned dependencies, so installing this experimental runtime cannot hold back an Omarchy system update. In particular, `systemd-libs` owns the embedded launcher's `libsystemd.so.0`. Package archive members and directories must be owned by `root:root`; directories use `0755`, executables and the bridge use `0755`, and QML, QML metadata, capability definitions, provider profiles, and policy data use `0644`. Libraries reached through Qt, including `libxkbcommon` and the GL implementation, remain in `qt6-base`'s package dependency closure rather than being duplicated as direct dependencies here.

The packaged desktop opener is dormant under the same rules. It accepts only bounded HTTPS URLs whose normalized origin exactly matches the granted demand scope and whose invocation carries a fresh user gesture. It revalidates the URL and scope at the trusted provider boundary, rejects user information and non-default ports, checks the fixed root-owned launch paths and their parent directories, and detaches the browser launch into the user's systemd manager. `browser-tab` uses `/usr/bin/xdg-open`; `web-app-window` uses `/usr/bin/chromium --app=`. No browser, desktop bus, or arbitrary URL authority is exposed inside the plugin sandbox.

The verifier syntax-checks every installed shell QML file, imports the installed native module with `ModuleProbe.qml`, and verifies its runtime invariants. Imports supplied only by the complete Omarchy shell context, including `qs.Ui`, are exercised by the live shell validation rather than resolved by this standalone package check.

The touch injector currently compiles against Qt's private QPA API, but the package deliberately does not translate that implementation detail into a package-manager lock. It is built and tested with the Qt supplied by Omarchy and declares `omarchy`, `qt6-base`, and `qt6-declarative` as ordinary unversioned dependencies. If an incompatible Qt release reaches the system before a matching runtime build, the runtime may be unavailable until rebuilt, but it must not block the system update. The package builder copies the committed dependency contract unchanged into the package metadata. Both the staged-payload verifier and archive verifier require that exact package-name set and reject added version constraints, missing owners, or package metadata that differs from the installed contract.

The Arch package definition lives in `packaging/arch`. Its build helper archives the committed `native/plugin-runtime` tree and passes the dependency contract from that exact source archive unchanged into package metadata. It never installs the result. Build it into an explicit output directory, then exercise verification, install, and ordinary removal inside a disposable pacman root:

```bash
archive=$(native/plugin-runtime/packaging/arch/build-package.sh /tmp/omarchy-plugin-security-package)
sudo native/plugin-runtime/packaging/arch/test-package-lifecycle.sh "$archive"
```

The lifecycle test extracts the final archive with its numeric ownership, runs both existing package verifiers against that exact payload, compares its dependency metadata with the installed configured contract, checks pacman's `.MTREE` view, disables scriptlets and points hooks at an empty directory, and proves that package installation and removal leave representative system and user v1 plugin trees plus unrelated Omarchy files byte-for-byte unchanged.

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

When activated, the singleton `PluginManager` opens only fixed trusted roots, scans activation records off the UI thread, and prepares each verified plugin in its own runtime slot. After the authenticated session reports its running state, the manager validates the current binding and declared surface policy before publishing manager-owned bar, panel, and overlay rows. QML attachment requires the matching opaque surface key. Failed scans retain the last good catalog, while removal or revision replacement withdraws rows and tears down endpoints before the runtime root.
