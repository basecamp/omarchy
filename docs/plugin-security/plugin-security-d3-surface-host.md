# D3 Trusted Surface Host Integration

## Result

The reference path now binds a named schema-v2 surface and one B2 `ActivationBinding` to a host-owned envelope before the D2 render session allocates memory. `surface-host` consumes the manifest parser's canonical surface object, selects one named declaration, verifies its plugin against the activation binding, applies a bounded role policy, creates the trusted geometry and DPR allocation from the binding generation, and composes the D2 render session with the C6 `RemotePluginSurface`. Arbitrary QML still controls every pixel and local animation inside that allocation; it receives no Quickshell object, compositor handle, layer, monitor, z-order, lock-screen, inspection, or policy authority.

The module is standalone under `native/plugin-runtime/surface-host/`. Root build and installed-shell wiring remain later integration work, so D3 does not collide with D1's authenticated channel integration or claim that schema v2 is enabled for users.

## Frozen host policy

- A plugin may declare at most eight named surfaces. Version 1 accepts only `bar-embedded`, `desktop-overlay`, and `panel`; each role has an independent geometry ceiling, and declared frame rate is limited to 1–60 frames per second.
- Logical geometry must fit both the declaration and the role ceiling. The host chooses the surface id, launch/surface generation, actual logical size, rational DPR, pixel geometry, mapping capacity, and placement implied by the role.
- Version 1 rejects unconditional keyboard focus. `after-gesture` permits keys only after a trusted pointer-press or touch gesture inside the current host-clipped input region. A no-focus surface can receive a trusted press plus its exact button release, or a bounded touch begin/update/end lifecycle, through a host-only transient capture gate. The capture is cleared on lock or teardown, never changes persistent focus, and cannot enable keys.
- Static surfaces use the complete assigned rectangle. `dynamic-bounded` surfaces may replace their regions with zero to 16 nonempty rectangles entirely inside the host allocation; an empty set makes the surface fully click-through. Invalid updates preserve the prior trusted region set.
- Lock-screen visibility is unsupported and a manifest asking for it is rejected. The lock bit latches even during profile/allocation negotiation, preventing a late acknowledgement from making a surface visible. For an active surface, entering the lock screen clears focus and suspends it. Any focus-clear or suspend failure closes the session while the lock remains latched; only an explicit trusted unlock can resume or continue negotiation.
- The host enforces the declared frame rate before shared-memory copy or QML upload using an injected monotonic clock and an overflow-safe integer period. Structurally valid excess `FRAME_READY` messages are coalesced as nonfatal drops; malformed envelope/payload/identity fields still reach D2 and fail under its protocol rules. A monotonic-clock rollback closes the surface rather than weakening the budget.
- The host inspector reads immutable plugin id, exact revision digest and policy fingerprint from the single activation binding, named surface, role, assigned geometry/DPR, host surface identity/generation, frame sequence, pacing-drop count, input-region count, connection state, focus, lock, and termination state. Its only reference actions are opening the trusted permission UI and terminating the surface. Those actions call a host-owned authority interface that is never injected into plugin QML.

## Failure behavior

The controller distinguishes a nonfatal D2 frame rejection or rate-coalesced frame from a terminal render failure by inspecting the render-session phase. A stale, concurrent, or early frame may return false while the phase stays active and the last trusted presentation remains visible. A malformed envelope, incompatible lifecycle transition, transport loss, monotonic-clock failure, or peer loss moves the D2 session to failed/disconnected; C6 then clears pixels, focus, visibility, and input eligibility. Termination is idempotent.

The initial software render profile still publishes complete premultiplied RGBA frames. It has no partial-damage metadata, ShaderEffect, particles, GPU renderer, IME, clipboard, drag and drop, accessibility, global shortcuts, popup delegation, or lock-screen surface support. D3 does not weaken those limitations to accommodate a fixture.

## Representative today-to-tomorrow mapping

| C10 fixture | Expressive content retained | Host-owned tomorrow |
|---|---|---|
| Pomodoro | Arbitrary animated bar QML, custom drawing, timer interaction | Named `timer` bar envelope, maximum 280×64, 30 FPS, full assigned input rectangle, no keyboard |
| Desktop pet | Transparent arbitrary QML, walking animation, irregular click target | Named `pet` desktop overlay, maximum 360×220, 30 FPS, at most 16 clipped dynamic regions, no keyboard or lock-screen visibility |
| Fake status | Custom panel QML and named broker operations | Named `statusPanel` panel, maximum 480×640, 30 FPS, keyboard only after a trusted in-region gesture; undeclared broker operations remain outside this surface module |

The QML `surfaceRole`, dimensions, or other object properties are presentation data and cannot override the manifest-derived policy. A requested `compositor` role, z-order field, unconditional focus, lock visibility, excessive geometry, missing named surface, or malformed policy fails before D2 allocation.

## Evidence

The D3 test loads all three C10 manifest fixtures, negotiates the real D2 profile/allocation lifecycle, publishes through the real B4 memfd transport, and exercises the real C6 input/focus transport. It proves pre-acknowledgement denial, exact activation/plugin/revision/policy/generation binding, role/geometry/DPR identity, static, empty click-through, and dynamic input clipping, no-focus press/release and touch lifecycles without keyboard authority, after-gesture keyboard focus, replay/stale identity denial, lock races during both negotiation phases, atomic lock failure, lock suspension/resume, enforced 30 FPS coalescing before copy/upload, clock-rollback teardown, host-owned inspection identity/actions, termination, nonfatal stale-frame preservation, fatal malformed-packet teardown, and rejection of lock-screen/compositor/z-order authority.

Run the focused suite with:

```bash
cmake -S native/plugin-runtime/surface-host -B build/plugin-surface-host -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-surface-host
ctest --test-dir build/plugin-surface-host --output-on-failure
```

Set `-DPLUGIN_SECURITY_SURFACE_HOST_SANITIZERS=ON` for the ASan/UBSan run. Actual Quickshell window placement, monitor selection, compositor focus, visual inspection affordance, installed service wiring, and disposable-VM interaction remain E1/E2/F2/F4/F5 work; this node freezes and proves the authority boundary they must consume.
