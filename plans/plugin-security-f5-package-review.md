# F5 package and acceptance review

## Current result

The native runtime builds and installs into the intended package layout, and the archive verifier successfully loaded both `PluginHostInfo` and the production `RemotePluginSurface` from the installed `Omarchy.PluginHost` QML ABI in an isolated staging tree. The final-tip archive contains the trusted host in `/usr/bin`, the worker outside `PATH` in `/usr/lib/omarchy/plugin-runtime`, the QML module in `/usr/lib/qt6/qml/Omarchy/PluginHost`, both permission/audit store CLIs, and the dormant graphical-session-scoped systemd user unit. The host's dynamic dependencies include Qt Core, libseccomp, and libsystemd with no RPATH/RUNPATH; launcher linkage is applied by `launcher/CMakeLists.txt` after the host target is created.

This is package-shape evidence, not a completed clean-install proof. The production host executable intentionally remains a long-running skeleton and `PluginHostInfo.available` remains false. The acceptance surface now fails if that property becomes true and labels the screenshot `ACTIVATION FEATURE-GATED`, so it cannot be cited as evidence that plugin activation, worker launch, broker traffic, or frame presentation is wired into the installed shell.

## Reproduced archive evidence

The companion patch [`omarchy-dev-plugin-runtime.patch`](../native/plugin-runtime/packaging/omarchy-dev-plugin-runtime.patch) applies cleanly to a clean clone of the packaging master used for this proof and deliberately omits makepkg-generated `pkgver` drift. A clean, detached Omarchy source clone at final PR candidate `b28f655f74ba35651797c143bdd907013fab13a7` produced this archive:

```text
/tmp/omarchy-pkgs-f5-final-b28f655f/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1953.gb28f655-1-x86_64.pkg.tar.zst
SHA256 766166c6ba959a461eed199d12a62b4ce4b1f6c36bec11c8cb41023ba445fe77
```

The package was built without `--nocheck`. Its Release `check()` run passed all 54 aggregate CTests. The checked-in verifier and its negative mutation self-test both pass against the resulting archive, including construction of the disconnected production surface type:

```bash
native/plugin-runtime/packaging/verify-package.sh /tmp/omarchy-pkgs-f5-final-b28f655f/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1953.gb28f655-1-x86_64.pkg.tar.zst
native/plugin-runtime/packaging/verify-package-test.sh /tmp/omarchy-pkgs-f5-final-b28f655f/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1953.gb28f655-1-x86_64.pkg.tar.zst
```

The archive and digest above supersede the historical `c19174a7`, `7aaa9b48`, intermediate `04f8776b`, and pre-hardening `27cea38d` package-shape runs. It includes the final dormant-integration and discovery/enum hardening corrections: the unit is conditional on the optional host binary, the package has no install script or enablement symlink, and neither first-run nor migration code enables or starts it. `pacman -Qip` reports `Install Script : No`; the focused systemd and plugin-runtime shell tests pass the dormant/no-end-user-route assertions. This proves the archive installs the unit file without activating it; a live user-manager inactive-state observation remains part of the fresh-VM gate.

The verifier now checks exact allowlists for the private runtime and QML module directories; regular-file, directory, ownership, and unsafe permission boundaries; the private worker's absence from `/usr/bin`; QML type metadata; x86-64 package identity; exact declared runtime dependencies; graphical-session service directives; protocol reporting; direct-worker fail-closed behavior; and an offscreen dynamic import from the extracted QML tree. All five installed ELF files are checked for their expected PIE/shared-object type, non-executable GNU stack, GNU RELRO, absence of RPATH/RUNPATH, bounded `DT_NEEDED` set, required direct dependencies, and successful `ldd -r` resolution.

`verify-package-test.sh <archive>` extracts one known-good archive and applies negative mutations for unexpected private/QML helpers, symlinks, setuid and writable modes, RPATH, non-PIE output, executable stack, missing RELRO, unexpected and unresolved dependencies, and non-root archive ownership. Each mutation must fail for its intended reason before the self-test reports success.

## Hosted builder integration seams

The official ISO helper invokes `makepkg --nodeps`, so newly declared `makedepends` are not resolved or even checked by that build step. The committed package workflow must either provision the native compiler, CMake/Ninja, Qt, seccomp, and systemd development inputs in the builder image before invoking the helper or change the helper contract; adding metadata alone is insufficient evidence that a clean hosted builder can compile the runtime.

The hosted package container is privileged for image construction but is not a compatible environment for the complete `check()` suite: nested Bubblewrap namespace probes, user-session/systemd behavior, and display/session-dependent tests can fail because of the outer container rather than the candidate. The ephemeral ISO workflow may therefore build the exact package with `--nocheck`, but that archive is acceptable only when the same source/package candidate has separately passed the complete native Debug and Release suites in their required environments plus archive verification and the negative verifier suite. `--nocheck` is never itself test evidence.

The first full Release check crashed from stack exhaustion in the permission contract. Core-dump analysis traced the failure to several fixed-capacity vectors allocating their backing arrays on the stack. Commit `c32121f3` preserves the same attacker-facing `FixedVector` capacity limits while moving backing storage off stack; the subsequent pre-integration 41-test build and the current clean 54-test build both passed. This is useful package-build evidence because the failure did not reproduce in the narrower development builds.

## Reproducibility blockers

- The `omarchy-dev` PKGBUILD modifications are captured as a companion patch but are not committed in `omarchy-pkgs`; the real sibling checkout remains unchanged. A production package cannot be reproduced through the normal packaging repository until the recipe lands there or equivalent package ownership is selected.
- The official ISO helper uses `makepkg --nodeps`; the hosted builder image does not yet guarantee the recipe's new native `makedepends`. Its privileged container also cannot run the full nested-sandbox/session/display `check()` suite, so the ephemeral ISO build needs an explicit `--nocheck` path paired with separately recorded native-suite evidence for the exact candidate.
- No sibling `omarchy-iso` checkout is available in this workspace. The required fresh ISO build and `omarchy-iso-test` run have not occurred, and there are no VM screenshots or collected service logs.
- The current graphical acceptance opens a generic Qt Quick `Window` that imports the packaged ABI. It proves Wayland-visible dynamic QML loading and the explicit unavailable state, not import from the production Quickshell process or a compositor-owned plugin surface.
- The aggregate build now compiles the production trusted bridge, render session, surface host, expressive surface, representative fixtures, and vertical proof tests, and the single installed QML module exports `RemotePluginSurface`. The service executable nevertheless remains a feature-gated host skeleton and does not yet compose those libraries into live plugin activation.

## Required completion run

After committing the package recipe, first build from a clean Omarchy checkout without `--nocheck` in a compatible native test environment and verify the resulting archive. Then use the provisioned hosted builder to create the ephemeral ISO package with `--nocheck` if its privileged container still cannot run nested sandbox/session/display checks, and follow the repository acceptance guide with a fresh ISO rather than `--reuse-base`:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

F5 closes only when that run shows the exact installed archive, a disabled and inactive graphical-session host skeleton, the worker absent from `PATH` and rejecting direct execution, an ABI-matched QML import under Wayland, and collected acceptance logs/screenshots. Functional plugin activation remains a separate production-host integration requirement and must not be inferred from this checkpoint.
