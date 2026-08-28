# G4 secure plugin release gate

## Current decision

G4 is not complete. The F0-F4 implementation, F6 representative migration evidence, and aggregate native build pass this preflight, but final authorization still requires accepted F5 fresh-install and graphical evidence. Building or installing the reference artifacts does not enable schema v2.

## Release checklist

| Gate | State | Evidence or remaining requirement |
| --- | --- | --- |
| One production QML module | Pass | `Omarchy.PluginHost` is registered once. Its installed module contains `PluginHostInfo` and `RemotePluginSurface`; the plain trusted-bridge library exists only for native tests and consumers. |
| Production targets in aggregate build | Pass | Root CMake builds the worker, launcher, broker/lifecycle stack, render session, trusted bridge, surface host, headless slice, expressive surface, product fixtures, embedded-bar and brokered-action slices, C11 adversarial harness, and F2 render proof in dependency order. |
| Package-shaped build | Refresh required | A prior fresh Release build with `BUILD_TESTING=OFF` built and installed the host, worker, permission/audit inspectors, and the single QML module, and its installed import path resolved both exported QML types. The later dormant-unit correction changed a packaged input, so F5 must reproduce this evidence from the final branch tip. |
| Debug aggregate | Pass | Fresh expanded aggregate: 54 of 54 tests, including real Bubblewrap, authenticated channels, malicious peers, arbitrary-QML rendering, lifecycle, permission/audit, brokered action, migration, and render proof. |
| Release aggregate | Pass | After the pidfd/reap correction in `bbf31c10`, fresh post-merge Debug and Release builds each passed all 54 tests outside managed confinement. The repaired Release `plugin-brokered-action` boundary then passed 100 of 100 fake-launch repetitions and 100 of 100 real-Bubblewrap repetitions. An earlier mixed-layout crash run remains excluded because source commit `c32121f3` landed between library and test compilation; core and object timestamps proved that separate ABI mixture. |
| Sanitizers and default stack | Pass for completed F0-F4 scope | Uniform ASan/UBSan E5/lifecycle tree passes six of six selected tests at the ordinary 8 MiB stack. F0-F2 retain their focused sanitizer evidence and documented exact-environment LeakSanitizer exclusions. |
| Feature-flag honesty | Pass | `omarchy-plugin-host` supports only version and launcher-prerequisite inspection and otherwise remains inert; `PluginHostInfo.available` is false. Discovery/revision defaults are disabled, the native permission inspector requires `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`, no end-user command routes to the native inspectors, and no first-run or migration path enables or starts the reference service. |
| Legacy honesty | Pass | Existing schema-v1 commands remain the explicitly unsafe compatibility path and are not described as granularly sandboxed. |
| F5 disposable-VM install and graphical acceptance | Pending | Accept the final package/archive provenance, clean install, real installed QML module, shell presentation, and fresh-ISO evidence. |
| F6 representative migrations | Pass | Twenty pinned real plugins produce deterministic migration results: 14 bounded scans and six fail-closed asset-limit outcomes. The E1/E2/E3 proof paths pass Debug, Release, and sanitizer validation, while unsupported capabilities and scanner blind spots remain explicit. |

## Security invariants rechecked

- Plugin identity comes from the kernel-bound launch and immutable activation binding, never an envelope payload.
- Three fixed role endpoints negotiate one generation before dispatch; stale roles, credentials, descriptors, and correlations fail closed.
- Arbitrary QML owns pixels and local animation only. The host owns allocation, placement, z-order, monitor, focus, input regions, pacing, inspection, and teardown.
- Provider effects require exact grants and durable redacted audit admission before effect. Revocation, shutdown, stale handles, malformed requests, and audit failure remain effect-free.
- Resource and request limits are fixed-capacity or trusted-monotonic. Clock regression and sustained excess terminate and enter health backoff before downstream dispatch.
- Disabled and removed activations are durably non-launchable before teardown; retained broker references are poisoned and reinstall receives a fresh generation.

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

These shell-suite limitations do not broaden the G4 claim: F5 still requires the matching package repository revision and disposable-VM/fresh-ISO acceptance before authorization.
