# C10 representative product fixtures

## Outcome

C10 adds three schema-v2 product fixtures under `native/plugin-runtime/fixtures/product/`. They are ordinary custom QML scenes, not uses of an Omarchy component library. The worker-facing seam in this isolated node is one authority-free fake runtime object with named operations; it exists only to let the scenes and service model execute before C5, C6, and C8 are integrated.

The fixtures demonstrate the intended compatibility split: plugin authors retain their scene graph, animation, layout, local state, and interaction code, while the host owns the surface envelope and the broker owns every system effect.

## Existing behavior to secure form

| Representative behavior | Fixture | QML kept inside the worker | Authority moved outside the scene |
|-------------------------|---------|----------------------------|-----------------------------------|
| Pomodoro bar widget with animation, local timer state, persistence, completion notification, and sound | `pomodoro` | Custom progress treatment, typography, animation, pointer interaction, timer state, and session count | `storage_read`, `storage_write`, `notification_send`, and `audio_play_cue` are named mock operations matching the B2 vocabulary |
| Transparent pet moving around the desktop | `pet` | Transparent root, hand-built character, shadow, animation, pointer interaction, and dynamically updated input geometry | The manifest requests a bounded `desktop-overlay`; monitor, z-order, frame rate, focus denial, lock-screen denial, dimensions, and enforcement of the reported input region remain host-owned |
| Basecamp-style status panel backed by an authenticated adapter | `fake-status` | Custom panel, list layout, item styling, service response model, and acknowledgement interaction | Only `fake_status_list` and `fake_status_acknowledge` are available; an undeclared `open_uri` request is deterministically denied by the mock rather than translated into ambient URL opening |

## Test boundary

`omarchy-plugin-product-fixtures-test` parses each real schema-v2 manifest with B1, resolves its declared QML entry point, loads the scene in a fresh `QQmlEngine`, and injects only the per-fixture fake runtime. It proves:

- the Pomodoro scene preserves local state and emits exactly its four named operations;
- the pet remains a custom transparent animated scene with no broker operation, no keyboard focus, a 30 FPS declaration, and one bounded moving input region;
- the fake service panel consumes three deterministic records through the enumerated list operation, acknowledges through the separate mutation operation, and cannot turn an undeclared URL request into host behavior;
- all three fixtures load without Quickshell objects, shell registries, filesystem APIs, process launchers, D-Bus, Wayland, or a live external account.

The test deliberately does not claim a security boundary around `QQmlEngine`. C5 supplies the sandboxed worker and restricted import/runtime environment, C6 supplies the trusted surface consumer, C8 supplies bounded production providers, and D2–D4 replace this fake object with authenticated channels. E1 and E2 own visual verification in the running shell; C10 is the deterministic product corpus they will consume.

## Run

```bash
cmake -S native/plugin-runtime/fixtures/product -B build/plugin-product-fixtures -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-product-fixtures
ctest --test-dir build/plugin-product-fixtures --output-on-failure
```
