# F5 package and acceptance review

## Current result

The native runtime builds and installs into the intended package layout, and the archive verifier successfully loads both `PluginHostInfo` and the production `RemotePluginSurface` from the installed `Omarchy.PluginHost` QML ABI in an isolated staging tree. The archive contains the trusted host in `/usr/bin`, the worker outside `PATH` in `/usr/lib/omarchy/plugin-runtime`, the QML module in `/usr/lib/qt6/qml/Omarchy/PluginHost`, both permission/audit store CLIs, and the graphical-session-scoped systemd user unit. The host's dynamic dependencies include Qt Core, libseccomp, and libsystemd with no RPATH/RUNPATH; launcher linkage is applied by `launcher/CMakeLists.txt` after the host target is created.

This is package-shape evidence, not a completed clean-install proof. The production host executable intentionally remains a long-running skeleton and `PluginHostInfo.available` remains false. The acceptance surface now fails if that property becomes true and labels the screenshot `ACTIVATION FEATURE-GATED`, so it cannot be cited as evidence that plugin activation, worker launch, broker traffic, or frame presentation is wired into the installed shell.

## Reproduced archive evidence

The companion patch [`omarchy-dev-plugin-runtime.patch`](../native/plugin-runtime/packaging/omarchy-dev-plugin-runtime.patch) applies cleanly to a clean clone of the packaging master used for this proof and deliberately omits makepkg-generated `pkgver` drift. A clean, detached Omarchy source clone at `c19174a77427404ccdcc2be9fc31287b14c25f95` produced this pre-rebase archive:

```text
/tmp/omarchy-pkgs-f5-clean-recipe/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1849.gc19174a-1-x86_64.pkg.tar.zst
SHA256 2dd8e061301aca9d0f183993d24afe0f12f6700aa549730b2d92fcd21ec06ab7
```

The package was built without `--nocheck`. Its Release `check()` run passed all 54 aggregate CTests, and the checked-in verifier passes against the resulting archive, including construction of the disconnected production surface type:

```bash
native/plugin-runtime/packaging/verify-package.sh /tmp/omarchy-pkgs-f5-clean-recipe/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1849.gc19174a-1-x86_64.pkg.tar.zst
```

The verifier now checks regular-file modes, the private worker's absence from `/usr/bin`, QML type metadata, x86-64 package identity, exact runtime dependencies, graphical-session service directives, protocol reporting, direct-worker fail-closed behavior, absence of RPATH/RUNPATH, and an offscreen dynamic import from the extracted QML tree.

The first full Release check crashed from stack exhaustion in the permission contract. Core-dump analysis traced the failure to several fixed-capacity vectors allocating their backing arrays on the stack. Commit `c32121f3` preserves the same attacker-facing `FixedVector` capacity limits while moving backing storage off stack; the subsequent pre-integration 41-test build and the current clean 54-test build both passed. This is useful package-build evidence because the failure did not reproduce in the narrower development builds.

## Reproducibility blockers

- The `omarchy-dev` PKGBUILD modifications are captured as a companion patch but are not committed in `omarchy-pkgs`; the real sibling checkout remains unchanged. A production package cannot be reproduced through the normal packaging repository until the recipe lands there or equivalent package ownership is selected.
- Commit `c19174a7` was exact clean-source evidence, but upstream `quattro` advanced before the proof was recorded. The branch must be rebased and this full clean-clone build, 54-test check, verifier, archive identity, and hash must be repeated from the final PR HEAD. The archive above is explicitly pre-rebase evidence and is not the final candidate.
- No sibling `omarchy-iso` checkout is available in this workspace. The required fresh ISO build and `omarchy-iso-test` run have not occurred, and there are no VM screenshots or collected service logs.
- The current graphical acceptance opens a generic Qt Quick `Window` that imports the packaged ABI. It proves Wayland-visible dynamic QML loading and the explicit unavailable state, not import from the production Quickshell process or a compositor-owned plugin surface.
- The aggregate build now compiles the production trusted bridge, render session, surface host, expressive surface, representative fixtures, and vertical proof tests, and the single installed QML module exports `RemotePluginSurface`. The service executable nevertheless remains a feature-gated host skeleton and does not yet compose those libraries into live plugin activation.

## Required completion run

After committing the package recipe, build from a clean Omarchy checkout without `--nocheck`, verify the resulting archive, then follow the repository acceptance guide with a fresh ISO rather than `--reuse-base`:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

F5 closes only when that run shows the exact installed archive, an enabled and active graphical-session host skeleton, the worker absent from `PATH` and rejecting direct execution, an ABI-matched QML import under Wayland, and collected acceptance logs/screenshots. Functional plugin activation remains a separate production-host integration requirement and must not be inferred from this checkpoint.
