# G4 secure plugin release gate

## Current decision

G4 is complete for opening the architecture discussion and draft reference PR for review. Final candidate `0dac331a8611c669801924394a2f28d94430e957` passes the F0-F6 reference gates, including exact package provenance and the dormant fresh-VM boundary. G4 does not authorize production activation or merge: the host remains inert, package ownership is not landed, and the broader VM aggregate retains five known non-plugin baseline failures.

## Release checklist

| Gate | State | Evidence or remaining requirement |
| --- | --- | --- |
| One production QML module | Pass | `Omarchy.PluginHost` is registered once. Its installed module contains `PluginHostInfo` and `RemotePluginSurface`; the plain trusted-bridge library exists only for native tests and consumers. |
| Production targets in aggregate build | Pass | Root CMake builds the worker, launcher, broker/lifecycle stack, render session, trusted bridge, surface host, headless slice, expressive surface, product fixtures, embedded-bar and brokered-action slices, C11 adversarial harness, and F2 render proof in dependency order. |
| Package-shaped build | Pass for exact reference candidate | A clean detached `0dac331a` package build passed all 55 Release checks, the archive verifier, and its negative mutation suite. The hosted pinned build produced package `4.0.0.r1.g0dac331-1`, and the VM identity overlay matched the exact installed host, worker, and QML bridge hashes. |
| Debug aggregate | Pass | Fresh final-candidate aggregate: 55 of 55 tests, including the F1 10,000-envelope exhaustion corpus, real Bubblewrap, authenticated channels, malicious peers, arbitrary-QML rendering, lifecycle, permission/audit, brokered action, migration, and render proof. |
| Release aggregate | Pass | Fresh final-candidate Debug and Release builds each passed all 55 tests outside managed confinement. The Release `plugin-brokered-action` boundary then passed 25 of 25 fake-launch repetitions and 25 of 25 real-Bubblewrap repetitions after the final hardening. Earlier post-merge evidence also includes 100 of 100 fake and 100 of 100 real repetitions after the pidfd/reap correction in `bbf31c10`. An earlier mixed-layout crash run remains excluded because source commit `c32121f3` landed between library and test compilation; core and object timestamps proved that separate ABI mixture. |
| Sanitizers and default stack | Pass for completed F0-F4 scope | Uniform ASan/UBSan E5/lifecycle tree passes six of six selected tests at the ordinary 8 MiB stack. F0-F2 retain their focused sanitizer evidence and documented exact-environment LeakSanitizer exclusions. |
| Feature-flag honesty | Pass | `omarchy-plugin-host` supports only version and launcher-prerequisite inspection and otherwise remains inert; `PluginHostInfo.available` is false. Discovery/revision defaults are disabled, the native permission inspector requires `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`, no end-user command routes to the native inspectors, and no first-run or migration path enables or starts the reference service. |
| Legacy honesty | Pass | Existing schema-v1 commands remain the explicitly unsafe compatibility path and are not described as granularly sandboxed. |
| F5 disposable-VM install and graphical acceptance | Pass for dormant/reference scope | Hosted run `33221534246` built a fresh ISO and passed all seven plugin-specific assertions: exact installed identity, prerequisites, direct-worker denial, disabled/inactive host service, graphical bridge presence, feature-gated label, and packaged QML import under Wayland. The aggregate suite still exited 1 on five exact known non-plugin baseline failures, so general release readiness remains open. |
| F6 representative migrations | Pass | Twenty pinned real plugins produce deterministic migration results: 14 bounded scans and six fail-closed asset-limit outcomes. The E1/E2/E3 proof paths pass Debug, Release, and sanitizer validation, while unsupported capabilities and scanner blind spots remain explicit. |

## Final hosted reference evidence

Successful hosted run [`33221534246`](https://github.com/jacob-vincent-mink/omarchy/actions/runs/33221534246), orchestration commit `38ee76418e82b101d924e806f125a754d6955b4e`, pinned candidate `0dac331a8611c669801924394a2f28d94430e957`, `omarchy-iso` `268bac16d351a21d867e37565738f458b11cb06c`, `omarchy-pkgs` `a8c9e2982e965d140adcbe3138fa44c2d538d60b`, and exact Arch build/test image digests. The retained artifact is `f5-fresh-iso-0dac331a8611c669801924394a2f28d94430e957`. ISO SHA-256 is `05b0a0bc7ed2e948c7f331a60ff01b17755edc61ce4b503336d794c63172696f`; package `4.0.0.r1.g0dac331-1` SHA-256 is `98d8ca0b000292f61d6b51a4011513b97efc43d42d244c7c3ef113e4fcbbdfb9`.

The official package-builder container used an exact logged `--nocheck` adaptation because its privileged environment cannot run the nested-sandbox/session/display checks. This is not counted as test evidence: the candidate separately passed fresh Debug and Release 55/55 native suites, and both package verifiers passed before VM boot. The acceptance harness also used an exact logged observation-only PSM 6 plus PSM 3 OCR patch after pinned PSM 6 reproducibly omitted selected green installer text.

The VM installed host SHA-256 `83bcf8f6b2dc6011075133ee1b8616a4fac1b4878ae6702a84fecbc216ea1c8f`, worker SHA-256 `cf99a09e187d5a3e10f3249b5aa83f86e542edbd4aa6c9aec307e760b0dde3b9`, and bridge SHA-256 `7b75d877e372518d304fcaf084a2adf86a335187deeb3f0012c48d016e93162c`. Provenance records `plugin_acceptance=pass` and `aggregate_acceptance=failed_known_baseline`: launcher shortcut, menu shortcut, universal-clipboard Chromium launch, browser window launch, and style submenu visibility were the exact five non-plugin failures. G4 therefore authorizes review of the dormant reference boundary while keeping production activation and general release readiness open.

## Security invariants rechecked

- Plugin identity comes from the kernel-bound launch and immutable activation binding, never an envelope payload.
- Three fixed role endpoints negotiate one generation before dispatch; stale roles, credentials, descriptors, and correlations fail closed.
- Arbitrary QML owns pixels and local animation only. The host owns allocation, placement, z-order, monitor, focus, input regions, pacing, inspection, and teardown.
- Provider effects require exact grants and durable redacted audit admission before effect. Revocation, shutdown, stale handles, malformed requests, and audit failure remain effect-free.
- Resource and request limits are fixed-capacity or trusted-monotonic. Clock regression and sustained excess terminate and enter health backoff before downstream dispatch.
- Disabled and removed activations are durably non-launchable before teardown; retained broker references are poisoned and reinstall receives a fresh generation.

## Final production-code hostile scan

The final scan excluded tests, fixtures, proofs, and experiments and inspected every production source under `native/plugin-runtime` for process escape, ambient desktop authority, unbounded input, unchecked size arithmetic, exception crossings, unknown enum handling, pre-audit provider effects, and unsafe filesystem traversal.

Three fail-closed corrections resulted. Discovery now opens `manifest.json` with `O_NOFOLLOW | O_NONBLOCK`, verifies the opened descriptor is a bounded regular file, and reads in fixed chunks without ever appending beyond one MiB; a FIFO regression proves a substituted special file cannot block discovery. The selected-endpoint state machine now rejects an unknown direction before consulting either direction's correlation table. Surface creation and expressive placement now reject unknown role and keyboard-focus values before allocation or any placement-authority callback instead of mapping an unknown role to desktop overlay.

Focused Debug, Release, and ASan/UBSan runs pass the discovery contract, wire contract, surface-host tree, and expressive-surface tree. LeakSanitizer itself is unavailable under the managed ptrace environment, so the sanitizer runs use `detect_leaks=0`; AddressSanitizer and UndefinedBehaviorSanitizer remain active.

The final aggregate audit found that the standalone F1 exhaustion executable was not registered by root CMake. It is now part of the aggregate, raising the complete suite from 54 to 55 tests while preserving its standalone campaign. The same audit exposed a scheduling race only in the fake channel peer: the peer could exit after its render WELCOME but before the host's required post-negotiation pidfd check. The fixture now blocks `SIGUSR1` before negotiation and exits only after the trusted test releases that barrier, proving post-readiness death deterministically without weakening production liveness. Eight repeated fake-channel runs, eight real-Bubblewrap channel runs, and both 55-test aggregates pass.

No production `system` or `popen` call exists. Process execution is limited to the pinned Bubblewrap launcher and the advisory, non-activated migration-report scanner; fork/exec peers elsewhere are test programs. Worker `HOME` and `XDG_RUNTIME_DIR` references validate the synthetic sandbox environment, while the native audit/grant inspectors use the trusted caller's state directory and are not routed as end-user commands. Provider effects remain behind broker authorization and durable audit admission. The remaining `QFile::readAll` uses consume files from the already bounded immutable worker revision; the migration reporter's scanner and target reads remain advisory-only and cannot grant or activate authority.

## Remaining product boundary

The native components are a reviewable reference, not an enabled plugin service. `host/main.cpp` does not compose discovery, activation, supervisor, broker dispatch, render pumping, or shell registration. The user unit is guarded by the optional host executable and remains disabled; no migration, first-run script, or end-user router command activates the reference. Enabling schema v2 requires a later trusted product host and rollout decision after G4; setting the native permission inspector's environment variable alone cannot activate a plugin.

The former Release teardown blocker is resolved by `bbf31c10`. The accepted pidfd readiness set is deliberately limited to `POLLIN` and `POLLIN | POLLHUP`, and direct-child reap now uses a bounded `WNOHANG` retry after pidfd exit readiness. Fresh post-merge aggregate runs and the repeated real-Bubblewrap stress above exercise that boundary.

The component-specific sanitizer options are not a safe aggregate switch: enabling only dependency options can instrument static libraries without linking the sanitizer runtime into every consumer. G4 used uniform compiler and executable-linker flags across the selected tree. A future CI convenience option should apply instrumentation uniformly while retaining the documented uninstrumented exact-environment sandbox helper.

## Post-upstream-merge regression evidence

The regression lane ran after merge commit `dcb7e7fd` on 2026-08-28 from newly configured build directories:

- Debug `/tmp/omarchy-postmerge-debug-MgNy1F`: configured with `BUILD_TESTING=ON`, built all 391 Ninja edges, and passed 54 of 54 CTest cases outside managed confinement.
- Release `/tmp/omarchy-postmerge-release-lfFFs2`: configured with `BUILD_TESTING=ON`, built all 391 Ninja edges, and passed 54 of 54 CTest cases outside managed confinement.
- The Release brokered-action executable passed 100 of 100 fake-launch runs and 100 of 100 real `/usr/bin/bwrap` runs outside managed confinement.
- Focused repository tests passed for git URL validation, plugin add, plugin-security inventory, plugin-security aggregate inventory, and QML text-format enforcement.
- `./test/cli` passed completely with `OMARCHY_PKGS_PATH=/tmp/omarchy-pkgs-f5-clean-master` and `OMARCHY_ISO_PATH=/tmp/omarchy-iso-f5`. The runner emitted only the known managed-filesystem warning while probing the user runtime lock path.

Both companion paths were clean Git checkouts for this run: `omarchy-pkgs` at `b1e3b4c2e4ce9e14e48c0528a73aa7a1bae1e844` and `omarchy-iso` at `268bac16d351a21d867e37565738f458b11cb06c`.

The aggregate `./test/shell` run completed but reported seven failing files out of 212. None was a plugin-security test or a failure introduced by this branch:

- `config-test.sh`, `snapper-test.sh`, and `unowned-system-paths-test.sh` require a companion `omarchy-pkgs` revision containing `pkgbuilds/omarchy-settings-dev/PKGBUILD`; the pinned clean companion revision does not contain that recipe. This is explicit cross-repository version skew, not accepted package evidence.
- `launch-about-test.sh` inherited the agent environment's `NO_COLOR=1`; the isolated test passed after unsetting that variable.
- `network-qr-test.sh` passed immediately in isolation, so its aggregate failure was transient and was not reproduced.
- `theme-install-guards-test.sh` expects its missing-helper case to have no `omarchy-git-url-check` on `PATH`, but this installed system exposes `/usr/bin/omarchy-git-url-check` even under a minimal `/usr/bin` path.
- `windows-vm-compose-test.sh` reached a managed-sandbox denial while trying to migrate the installed user's real credentials path. It was not rerun outside confinement because doing so could mutate real user state.

These shell-suite limitations do not broaden the G4 claim. The final F5 hosted run closes the exact dormant/reference install boundary, while committed package ownership, production host composition and activation, and a generally green fresh-ISO baseline remain required for release readiness.
