# E2 Expressive Arbitrary-QML Surface Slice

## Outcome

E2 preserves the feature that makes current Omarchy plugins compelling: a plugin may author an arbitrary Qt Quick scene, including transparency, animation, custom drawing, irregular interaction, pets, drawers, and other non-component-library UI. The scene remains untrusted and renders in the sandboxed worker. The trusted shell receives only copied pixels and authenticated bounded input messages.

The standalone slice is `native/plugin-runtime/expressive-surface/`. It composes the existing C10 pet fixture with the C5 arbitrary-QML worker, D2 frame session, B4 sealed shared-memory transport, C6 trusted bridge, and D3 named surface host. It adds only a host-side admission registry for compositor decisions that QML must never own.

## Proof

- The unchanged C10 `Pet.qml` loads through the arbitrary-QML worker and renders a frame containing both fully transparent and visible pixels. No declarative component library or restricted scene grammar is introduced.
- The unchanged C10 scene is also instantiated as authored and its real infinite `NumberAnimation` advances `petX`; this is an executable QML proof, not a source-text assertion. D3's authenticated focus and input packets are decoded and delivered through the real worker runtime using its host-created synthetic pointer/touch devices.
- An empty input-region set is fully click-through. A disjoint two-rectangle set accepts only inside points, while pointer release and touch update/end remain captured outside the original region until their exact lifecycle ends.
- The desktop-overlay policy never acquires persistent keyboard focus. Key delivery is denied, and host, bridge, and worker focus observations are all false after pointer and touch lifecycles.
- The host drops a frame above the manifest's 30 FPS ceiling before trusted copy/upload and preserves the last valid pixels. A frame at the next budget boundary is admitted.
- The new fixed-capacity registry is per plugin and admits at most eight surfaces. It rejects duplicate names/IDs, zero or oversized geometry, unknown/off-monitor placement, and a ninth surface.
- A trusted placement authority, not QML, selects the monitor and coordinates. Layer is derived from the validated D3 surface role, keyboard policy and FPS come from the manifest policy, and geometry is checked against both manifest and monitor bounds with subtraction-based arithmetic.

## Authority boundary

Arbitrary QML controls its local scene graph, animations, opacity, and the proposed bounded input-region geometry. It does not create a native window, choose a monitor, set layer-shell anchors, select raw z-order, bypass the per-plugin surface budget, request lock-screen visibility, acquire keyboard focus, or raise its frame rate. Those remain host decisions.

The `PlacementAuthority` interface is a trusted compositor seam. Production composition must implement it from host monitor/work-area policy; plugin bytes, QML properties, manifest extension keys, and worker messages are not valid placement authority. D3 remains the owner of authenticated render/input lifecycle and pacing. E2 does not add compositor, broker, grant, or system APIs to the worker.

## Verification

Configure and run the standalone proof with:

```bash
cmake -S native/plugin-runtime/expressive-surface -B /tmp/omarchy-e2 -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-e2 -j2
ctest --test-dir /tmp/omarchy-e2 --output-on-failure -R '^plugin-expressive-surface$'
```

Repeat with `-DCMAKE_BUILD_TYPE=Release`, and with `-DPLUGIN_SECURITY_EXPRESSIVE_SURFACE_SANITIZERS=ON` for ASan/UBSan.
