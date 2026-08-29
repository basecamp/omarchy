# F5 package and acceptance review

## Current result

The native runtime builds and installs into the intended package layout, and the archive verifier successfully loaded both `PluginHostInfo` and the production `RemotePluginSurface` from the installed `Omarchy.PluginHost` QML ABI in an isolated staging tree. The exact-candidate archive contains the trusted host in `/usr/bin`, the worker outside `PATH` in `/usr/lib/omarchy/plugin-runtime`, the QML module in `/usr/lib/qt6/qml/Omarchy/PluginHost`, both permission/audit store CLIs, and the dormant graphical-session-scoped systemd user unit. The host's dynamic dependencies include Qt Core, libseccomp, and libsystemd with no RPATH/RUNPATH; launcher linkage is applied by `launcher/CMakeLists.txt` after the host target is created.

The exact dormant/reference clean-install gate is complete. The production host executable intentionally remains a long-running skeleton and `PluginHostInfo.available` remains false. The acceptance surface fails if that property becomes true and labels the screenshot `ACTIVATION FEATURE-GATED`, so this evidence cannot be cited as proof that plugin activation, worker launch, broker traffic, or frame presentation is wired into the installed shell.

## Reproduced archive evidence

The companion patch [`omarchy-dev-plugin-runtime.patch`](../native/plugin-runtime/packaging/omarchy-dev-plugin-runtime.patch) applies cleanly to a clean clone of the packaging master used for this proof and deliberately omits makepkg-generated `pkgver` drift. A clean, detached Omarchy source clone at final PR candidate `0dac331a8611c669801924394a2f28d94430e957` produced this archive:

```text
/tmp/omarchy-pkgs-f5-final-0dac331a/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1957.g0dac331-1-x86_64.pkg.tar.zst
SHA256 137b70b28e69a62f01d6923d949b40f6e0db318ed868fa01a5d0ab4f58e60208
```

The package was built without `--nocheck`. Its Release `check()` run passed all 55 aggregate CTests. The checked-in verifier and its negative mutation self-test both pass against the resulting archive, including construction of the disconnected production surface type:

```bash
native/plugin-runtime/packaging/verify-package.sh /tmp/omarchy-pkgs-f5-final-0dac331a/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1957.g0dac331-1-x86_64.pkg.tar.zst
native/plugin-runtime/packaging/verify-package-test.sh /tmp/omarchy-pkgs-f5-final-0dac331a/pkgbuilds/omarchy-dev/omarchy-dev-4.0.0.r1957.g0dac331-1-x86_64.pkg.tar.zst
```

The archive and digest above supersede the historical `c19174a7`, `7aaa9b48`, intermediate `04f8776b`, pre-hardening `27cea38d`, pre-exhaustion-registration `b28f655f`, and pre-acceptance-fix `3efa25b9` package-shape runs. Its Release package check passed 55/55 aggregate CTests, including the deterministic 10,000-case envelope/resource-cap exhaustion proof. It includes the final dormant-integration, discovery/enum hardening, and deterministic compositor-state acceptance correction: the unit is conditional on the optional host binary, the package has no install script or enablement symlink, and neither first-run nor migration code enables or starts it. `pacman -Qip` reports `Install Script : No`; the focused systemd and plugin-runtime shell tests pass the dormant/no-end-user-route assertions. The hosted fresh-VM evidence below confirms the installed user service remains disabled and inactive.

The verifier now checks exact allowlists for the private runtime and QML module directories; regular-file, directory, ownership, and unsafe permission boundaries; the private worker's absence from `/usr/bin`; QML type metadata; x86-64 package identity; exact declared runtime dependencies; graphical-session service directives; protocol reporting; direct-worker fail-closed behavior; and an offscreen dynamic import from the extracted QML tree. All five installed ELF files are checked for their expected PIE/shared-object type, non-executable GNU stack, GNU RELRO, absence of RPATH/RUNPATH, bounded `DT_NEEDED` set, required direct dependencies, and successful `ldd -r` resolution.

`verify-package-test.sh <archive>` extracts one known-good archive and applies negative mutations for unexpected private/QML helpers, symlinks, setuid and writable modes, RPATH, non-PIE output, executable stack, missing RELRO, unexpected and unresolved dependencies, and non-root archive ownership. Each mutation must fail for its intended reason before the self-test reports success.

## Hosted builder integration seams

The official ISO helper invokes `makepkg --nodeps`, so newly declared `makedepends` are not resolved or even checked by that build step. The committed package workflow must either provision the native compiler, CMake/Ninja, Qt, seccomp, and systemd development inputs in the builder image before invoking the helper or change the helper contract; adding metadata alone is insufficient evidence that a clean hosted builder can compile the runtime.

The hosted package container is privileged for image construction but is not a compatible environment for the complete `check()` suite: nested Bubblewrap namespace probes, user-session/systemd behavior, and display/session-dependent tests can fail because of the outer container rather than the candidate. The ephemeral ISO workflow may therefore build the exact package with `--nocheck`, but that archive is acceptable only when the same source/package candidate has separately passed the complete native Debug and Release suites in their required environments plus archive verification and the negative verifier suite. `--nocheck` is never itself test evidence.

## Hosted fresh-ISO evidence

Hosted run [`33221534246`](https://github.com/jacob-vincent-mink/omarchy/actions/runs/33221534246), orchestrated by ephemeral commit `38ee76418e82b101d924e806f125a754d6955b4e`, targeted exact Omarchy commit `0dac331a8611c669801924394a2f28d94430e957`, official `omacom/omarchy-iso` commit `268bac16d351a21d867e37565738f458b11cb06c`, official `omacom/omarchy-pkgs` commit `a8c9e2982e965d140adcbe3138fa44c2d538d60b`, Arch build image `archlinux/archlinux@sha256:b7a2cf351dd0aebb189d366836047291bf0b4e0d2fc9bd35037a3a3bd719af9d`, and Arch test image `archlinux:base-devel@sha256:68bfc3b0d277b08a99101dc9b94aaa03e5ae70cf1b4fb965c03b2b87b915760d`. The official package-builder invocation was changed ephemerally from `--nodeps` to `--nodeps --nocheck` after seeding its exact build image with the declared native prerequisites. This package-container step is explicitly separate from the exact candidate's independently passing fresh Debug and Release 55/55 native suites and the local clean-source package `check()` proof above.

The workflow concluded successfully and retained artifact `f5-fresh-iso-0dac331a8611c669801924394a2f28d94430e957` (artifact ID `9705807771`). It produced fresh ISO SHA-256 `05b0a0bc7ed2e948c7f331a60ff01b17755edc61ce4b503336d794c63172696f` and package `omarchy-dev 4.0.0.r1.g0dac331-1` with SHA-256 `98d8ca0b000292f61d6b51a4011513b97efc43d42d244c7c3ef113e4fcbbdfb9`. Both the archive verifier and negative mutation suite passed before VM boot. The installed identity overlay then matched host SHA-256 `83bcf8f6b2dc6011075133ee1b8616a4fac1b4878ae6702a84fecbc216ea1c8f`, worker SHA-256 `cf99a09e187d5a3e10f3249b5aa83f86e542edbd4aa6c9aec307e760b0dde3b9`, and bridge SHA-256 `7b75d877e372518d304fcaf084a2adf86a335187deeb3f0012c48d016e93162c`.

All seven plugin-specific installed assertions passed: package artifacts and prerequisites were present; direct worker launch was denied; the host service remained disabled and inactive; the graphical session exposed the bridge; the bridge reported `ACTIVATION FEATURE-GATED`; and the packaged QML module loaded under Wayland while preserving its unavailable state. The full acceptance suite still exited 1 on the exact five known non-plugin baseline failures: launcher shortcut, menu shortcut, universal clipboard Chromium launch, browser window launch, and style submenu visibility. The workflow's success condition required that exact allowlisted baseline set and a passing plugin-specific test, and provenance records `aggregate_acceptance=failed_known_baseline` alongside `plugin_acceptance=pass`. This closes the dormant/reference F5 gate, not the production activation or generally green release gate.

Earlier hosted attempts that stopped in workflow orchestration, runner-capacity, or environment preparation before the VM assertions are not product evidence. Their only value is documenting the builder seams that the exact pinned run above must resolve; publication should cite only the final run and its retained artifact.

The exact pinned acceptance harness also produced a reproducible OCR false negative: its Tesseract PSM 6 preprocessing omitted the selected green `Yes, install without encryption` text that was visibly present in the retained screenshot, while PSM 3 read it. The superseding ephemeral proof combines the official PSM 6 output with PSM 3 through an exact logged harness patch. A successful run must retain that patch and provenance; the adaptation improves observation only and does not alter the ISO, guest, or assertion sequence.

The first full Release check crashed from stack exhaustion in the permission contract. Core-dump analysis traced the failure to several fixed-capacity vectors allocating their backing arrays on the stack. Commit `c32121f3` preserves the same attacker-facing `FixedVector` capacity limits while moving backing storage off stack; the subsequent pre-integration 41-test build and the current clean 55-test build both passed. This is useful package-build evidence because the failure did not reproduce in the narrower development builds.

## Reproducibility blockers

- The `omarchy-dev` PKGBUILD modifications are captured as a companion patch but are not committed in `omarchy-pkgs`; the real sibling checkout remains unchanged. A production package cannot be reproduced through the normal packaging repository until the recipe lands there or equivalent package ownership is selected.
- The official ISO helper uses `makepkg --nodeps`; the hosted builder image does not yet guarantee the recipe's new native `makedepends`. Its privileged container also cannot run the full nested-sandbox/session/display `check()` suite, so the ephemeral ISO build needs an explicit `--nocheck` path paired with separately recorded native-suite evidence for the exact candidate.
- The hosted proof used exact pinned companion commits and an ephemeral workflow rather than a committed package-repository recipe. Its retained logs and screenshots close the dormant/reference clean-install gate, but the full acceptance aggregate retains five explicitly known non-plugin baseline failures.
- The graphical acceptance opens a generic Qt Quick `Window` that imports the packaged ABI and separately observes the bridge in the graphical session. It proves Wayland-visible dynamic QML loading and the explicit unavailable state, not a compositor-owned live plugin surface.
- The aggregate build now compiles the production trusted bridge, render session, surface host, expressive surface, representative fixtures, and vertical proof tests, and the single installed QML module exports `RemotePluginSurface`. The service executable nevertheless remains a feature-gated host skeleton and does not yet compose those libraries into live plugin activation.

## Remaining production completion

Land the package recipe, make the official hosted builder provision its declared native inputs, upstream the OCR hardening, and restore a generally green fresh-ISO acceptance baseline. After the production host composes discovery, lifecycle, broker, render, and shell registration, rerun the disposable-VM suite against live activation rather than the intentionally unavailable reference:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

The dormant/reference F5 criteria are complete. Functional plugin activation remains a separate production-host integration requirement and must not be inferred from this checkpoint.
