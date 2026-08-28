# G4 secure plugin release gate

## Current decision

G4 is not complete. The F0-F4 implementation, F6 representative migration evidence, and aggregate native build pass this preflight, but final authorization still requires accepted F5 fresh-install and graphical evidence. Building or installing the reference artifacts does not enable schema v2.

## Release checklist

| Gate | State | Evidence or remaining requirement |
| --- | --- | --- |
| One production QML module | Pass | `Omarchy.PluginHost` is registered once. Its installed module contains `PluginHostInfo` and `RemotePluginSurface`; the plain trusted-bridge library exists only for native tests and consumers. |
| Production targets in aggregate build | Pass | Root CMake builds the worker, launcher, broker/lifecycle stack, render session, trusted bridge, surface host, headless slice, expressive surface, product fixtures, embedded-bar and brokered-action slices, C11 adversarial harness, and F2 render proof in dependency order. |
| Package-shaped build | Pass | A fresh Release build with `BUILD_TESTING=OFF` built and installed the host, worker, permission/audit inspectors, and the single QML module. The installed import path resolves both exported QML types. |
| Debug aggregate | Pass | Fresh expanded aggregate: 54 of 54 tests, including real Bubblewrap, authenticated channels, malicious peers, arbitrary-QML rendering, lifecycle, permission/audit, brokered action, migration, and render proof. |
| Release aggregate | Blocked | This preflight's fresh expanded aggregate passed 54 of 54 tests, but an independent fresh Release run passed 53 of 54 and consistently failed `plugin-brokered-action-bwrap` during action-channel teardown. The divergent result is an open release blocker until the owning boundary lands a fix and repeated outside-confinement proof. An earlier mixed-layout crash run remains excluded because source commit `c32121f3` landed between library and test compilation; core and object timestamps proved that separate ABI mixture. |
| Sanitizers and default stack | Pass for completed F0-F4 scope | Uniform ASan/UBSan E5/lifecycle tree passes six of six selected tests at the ordinary 8 MiB stack. F0-F2 retain their focused sanitizer evidence and documented exact-environment LeakSanitizer exclusions. |
| Feature-flag honesty | Pass | `omarchy-plugin-host` supports only version and launcher-prerequisite inspection and otherwise remains inert; `PluginHostInfo.available` is false. Discovery/revision defaults are disabled, the permission CLI requires `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`, and no product command routes schema v2 into execution. |
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

The installed native components are a reviewable reference, not an enabled plugin service. `host/main.cpp` does not compose discovery, activation, supervisor, broker dispatch, render pumping, or shell registration. Enabling schema v2 requires a later trusted product host and rollout decision after G4; setting the permission CLI environment variable alone cannot activate a plugin.

The independent Release teardown failure must be resolved before interpreting the aggregate as stable. A single passing run does not outweigh a reproducible fresh-build failure in a security-sensitive worker teardown path.

The component-specific sanitizer options are not a safe aggregate switch: enabling only dependency options can instrument static libraries without linking the sanitizer runtime into every consumer. G4 used uniform compiler and executable-linker flags across the selected tree. A future CI convenience option should apply instrumentation uniformly while retaining the documented uninstrumented exact-environment sandbox helper.
