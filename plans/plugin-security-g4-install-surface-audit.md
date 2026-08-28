# G4 installed-surface security audit

## Scope and result

Commit `c19174a7` passes the standalone CMake install-surface audit. A source archive of that exact commit was configured as Release with `BUILD_TESTING=OFF`, `CMAKE_INSTALL_PREFIX=/usr`, and `CMAKE_SKIP_RPATH=ON`, then built and installed into a fresh `DESTDIR`. The install manifest and filesystem agree on exactly seven regular files. No service unit is installed by CMake; the Arch packaging patch owns the user unit and the package verifier checks it separately.

This result does not close G4. Package provenance and graphical acceptance remain in F5, and the independently reproducible brokered-action teardown failure remains a release blocker.

## Installed inventory

| Mode | Installed path | Boundary |
| --- | --- | --- |
| `0755` | `/usr/bin/omarchy-plugin-host` | Inert trusted host skeleton and prerequisite inspector |
| `0755` | `/usr/bin/omarchy-plugin-permission-store` | Schema-v2-gated grant inspector/editor |
| `0755` | `/usr/bin/omarchy-plugin-audit-store` | Redacted audit inspector |
| `0755` | `/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker` | Private worker, deliberately absent from `/usr/bin` |
| `0755` | `/usr/lib/qt6/qml/Omarchy/PluginHost/libomarchy-plugin-host-bridge.so` | Single QML plugin library |
| `0644` | `/usr/lib/qt6/qml/Omarchy/PluginHost/qmldir` | `Omarchy.PluginHost` module descriptor |
| `0644` | `/usr/lib/qt6/qml/Omarchy/PluginHost/omarchy-plugin-host-bridge.qmltypes` | QML tooling type description |

All installed directories are mode `0755`. The fresh destination contains no symlinks, setuid or setgid entries, group- or world-writable entries, or filenames matching test, fixture, probe, fake, or malicious helpers. `BUILD_TESTING=OFF` still compiles the production render/session/bridge libraries into their consumers but installs no static libraries or test executables. A raw `DESTDIR` preserves the invoking user's ownership, so package ownership must be established from the package archive rather than inferred from this build.

## Executable and QML boundary

Direct execution of the private worker with no trusted inherited endpoints exits with status 78, produces no stdout, and reports that trusted Bubblewrap file descriptors 3, 4, and 5 are required. The worker does not appear in `/usr/bin`. The installed host reports `omarchy-plugin-host 0.1.0 envelope=1` but remains intentionally unable to activate a plugin.

The installed `qmldir` declares one `Omarchy.PluginHost` module and one plugin library. The generated type description exports exactly `PluginHostInfo 1.0` and `RemotePluginSurface 1.0`. `RemotePluginSurface` exposes host-observed surface state and signals but no QML-callable native method. An offscreen QML import instantiated both types successfully; the inert availability and disconnected/uncertain initial surface state remained intact.

All five installed ELF files are x86-64 position-independent executables or a shared object, have non-executable GNU stacks and GNU RELRO segments, resolve every `DT_NEEDED` entry on the build host, and contain no `DT_RPATH` or `DT_RUNPATH`. The host depends on Qt Core, libseccomp, libsystemd, and the standard runtime libraries. The worker depends on Qt Quick/QML/GUI/network, OpenGL dispatch libraries, libseccomp, and the standard runtime libraries. The QML bridge has the corresponding Qt/OpenGL dependencies but no libseccomp or libsystemd dependency. The two storage CLIs depend only on the standard C++ and C runtimes. A local CMake build does not by itself prove the Arch package's owner metadata or full hardening flags such as immediate binding; those belong to the clean package/archive inspection.

## Package-verifier comparison

`native/plugin-runtime/packaging/verify-package.sh` already verifies the expected host, private worker, storage CLIs, user service, QML files, modes, package architecture and declared dependencies, service directives, host version, worker direct-execution denial, absence of RPATH/RUNPATH on the host/worker/bridge, and a real offscreen QML import.

The install audit identified verifier coverage gaps that F5 should either close or explicitly accept:

- RPATH/RUNPATH inspection omits the permission and audit CLIs.
- The verifier does not reject unexpected files under the private runtime or QML module directories, test/helper artifacts, symlinks outside the individually required paths, setuid/setgid files, or group/world-writable entries.
- Package dependency metadata is checked, but actual `DT_NEEDED` entries and unresolved libraries are not compared with the intended runtime dependency boundary.
- Non-executable GNU stack, PIE/shared-object type, GNU RELRO, and package ownership are not asserted.
- The package intentionally contains the wider Omarchy tree, so any unexpected-file rule must be scoped to the plugin runtime install paths rather than implemented as a package-wide exact allowlist.

These are verifier-strength gaps, not violations observed in the exact-commit CMake install. F5 owns the packaging script and archive proof, so this audit records the findings without racing its active patch.

## Reproduction

```bash
git archive --format=tar c19174a7 -o /tmp/omarchy-g4-c19174a7/source.tar
tar -xf /tmp/omarchy-g4-c19174a7/source.tar -C /tmp/omarchy-g4-c19174a7/source
cmake -S /tmp/omarchy-g4-c19174a7/source/native/plugin-runtime -B /tmp/omarchy-g4-c19174a7/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_SKIP_RPATH=ON
cmake --build /tmp/omarchy-g4-c19174a7/build -j2
DESTDIR=/tmp/omarchy-g4-c19174a7/dest cmake --install /tmp/omarchy-g4-c19174a7/build
```

The audit then compared `install_manifest.txt` with all regular files under `DESTDIR`; enumerated modes, types, symlinks, and unsafe permission bits; ran the worker without inherited endpoints; loaded the installed QML module offscreen; and inspected every installed ELF with `file`, `ldd`, `readelf`, and `nm`.
