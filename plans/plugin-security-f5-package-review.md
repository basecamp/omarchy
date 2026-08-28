# F5 package and acceptance review

## Current result

The native runtime builds and installs into the intended package layout, and the archive verifier successfully loads the installed `Omarchy.PluginHost` QML ABI from an isolated staging tree. The archive contains the trusted host in `/usr/bin`, the worker outside `PATH` in `/usr/lib/omarchy/plugin-runtime`, the QML module in `/usr/lib/qt6/qml/Omarchy/PluginHost`, both permission/audit store CLIs, and the graphical-session-scoped systemd user unit. The host's dynamic dependencies include Qt Core, libseccomp, and libsystemd with no RPATH/RUNPATH; launcher linkage is applied by `launcher/CMakeLists.txt` after the host target is created.

This is package-shape evidence, not a completed clean-install proof. The production host executable intentionally remains a long-running skeleton and `PluginHostInfo.available` remains false. The acceptance surface now fails if that property becomes true and labels the screenshot `ACTIVATION FEATURE-GATED`, so it cannot be cited as evidence that plugin activation, worker launch, broker traffic, or frame presentation is wired into the installed shell.

## Reproduced archive evidence

The temporary package checkout is `/tmp/omarchy-pkgs-f5`; its modified recipe is `pkgbuilds/omarchy-dev/PKGBUILD`. The locally produced archive is:

```text
/tmp/omarchy-pkgs-f5/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1841.gb04ce25-1-x86_64.pkg.tar.zst
```

The package was rebuilt without `--nocheck`. Its Release `check()` run passed all 41 aggregate CTests, and the checked-in verifier passes against the resulting archive:

```bash
native/plugin-runtime/packaging/verify-package.sh /tmp/omarchy-pkgs-f5/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1841.gb04ce25-1-x86_64.pkg.tar.zst
```

The verifier now checks regular-file modes, the private worker's absence from `/usr/bin`, QML type metadata, x86-64 package identity, exact runtime dependencies, graphical-session service directives, protocol reporting, direct-worker fail-closed behavior, absence of RPATH/RUNPATH, and an offscreen dynamic import from the extracted QML tree.

The first full Release check crashed from stack exhaustion in the permission contract. Core-dump analysis traced the failure to several fixed-capacity vectors allocating their backing arrays on the stack. Commit `c32121f3` preserves the same attacker-facing `FixedVector` capacity limits while moving backing storage off stack; the subsequent package build and all 41 checks passed. This is useful package-build evidence because the failure did not reproduce in the narrower development builds.

## Reproducibility blockers

- The `omarchy-dev` PKGBUILD modifications are not committed in `omarchy-pkgs`; the real sibling checkout remains unchanged. A production package cannot be reproduced from this Omarchy commit until the recipe lands there or equivalent package ownership is selected.
- The archive version reports source commit `b04ce25`, but `OMARCHY_SRC` copied a shared worktree containing concurrent F5/F6 edits. The archive therefore does not correspond byte-for-byte to the named commit and must not be published as clean-source provenance evidence.
- No sibling `omarchy-iso` checkout is available in this workspace. The required fresh ISO build and `omarchy-iso-test` run have not occurred, and there are no VM screenshots or collected service logs.
- The current graphical acceptance opens a generic Qt Quick `Window` that imports the packaged ABI. It proves Wayland-visible dynamic QML loading and the explicit unavailable state, not import from the production Quickshell process or a compositor-owned plugin surface.
- The aggregate `native/plugin-runtime/CMakeLists.txt` builds the skeleton `bridge` module but does not add the production `trusted-bridge`, `render-session`, `surface-host`, or `expressive-surface` directories. Those implementations are therefore absent from the installed host, and the host does not compose the broker/lifecycle/surface path. Packaging more static archives would not fix that; the production host must first link and own the integrated runtime.

## Required completion run

After committing the package recipe, build from a clean Omarchy checkout without `--nocheck`, verify the resulting archive, then follow the repository acceptance guide with a fresh ISO rather than `--reuse-base`:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

F5 closes only when that run shows the exact installed archive, an enabled and active graphical-session host skeleton, the worker absent from `PATH` and rejecting direct execution, an ABI-matched QML import under Wayland, and collected acceptance logs/screenshots. Functional plugin activation remains a separate production-host integration requirement and must not be inferred from this checkpoint.
