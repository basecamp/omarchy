# A3 Remote-Frame Transport and Host Spike

## Question

Can an untrusted worker render arbitrary animated QML without a Wayland or X11 connection, and what is the smallest trusted integration needed for Omarchy's existing Quickshell process to consume those frames?

## Probe

The executable under `experiments/plugin-security/render-transport/` creates a dedicated `QQmlEngine`, loads an arbitrary `QQuickItem`, and renders it through `QQuickRenderControl` into a `QImage` using Qt Quick's software renderer. The test removes `WAYLAND_DISPLAY` and `DISPLAY`, selects the offscreen Qt platform, produces six frames, and requires at least two distinct frame hashes to prove that QML animation advances.

Qt's software adaptation must not call `QQuickRenderControl::initialize()`, `beginFrame()`, or `endFrame()`; those methods initialize and delimit graphics-API work. The software path sets a `QQuickRenderTarget` created from the `QImage` paint device and directly runs polish, sync, and render. This lifecycle distinction must be encoded in the worker rather than inferred from whether initialization happens to fail.

The adjacent `FrameConsumer.qml` demonstrates the only bridge available in ordinary QML without adding a native host module: an `Image` can consume copied file-backed frames with caching disabled. This is useful as a diagnostic fallback, but file creation, image decoding, cache invalidation, and polling make it unsuitable as the production frame transport.

## Initial transport decision

Use software rendering for the first security proof and keep the worker disconnected from Wayland, X11, D-Bus, and the GPU render node. Transfer bounded premultiplied RGBA frames through a host-created shared-memory object and notify `omarchy-plugin-host` over worker render/input FD 5. The daemon owns a separate authenticated session to the trusted Quickshell bridge; the worker never connects to the bridge directly. Use two fixed-capacity slots so the producer cannot resize memory after validation and the consumer can keep displaying the last valid frame while the worker writes the next one.

Each committed slot needs a fixed header layout containing protocol version, surface id, generation, logical size, pixel size, device-pixel ratio, stride, pixel format, damage rectangle count, payload length, and sequence values. The header remains untrusted because the worker can mutate its mapping. The host copies the header once, validates that local copy against its own allocation, and copies exactly the host-owned pixel extent into trusted memory before exposing it to the scene graph. A plugin-provided pointer, file path, texture id, or dimension is never consumed directly.

An unchanged even sequence around the copy is useful only as cooperative tear detection. It is not authentication: a malicious worker can race pixels without updating the sequence. That race is memory-safe when every offset and length comes from the trusted allocation and the consumer uploads only its bounded private copy, but the resulting pixels may be torn or adversarial—which is already within the plugin's pixel authority. If an atomic visual snapshot becomes a security property, shared writable slots need a stronger ownership-transfer primitive than a seqlock.

The first proof disables the software adaptation's partial-update optimization with `QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0`, so every published buffer is a self-contained frame. Re-enabling damage-based rendering requires a preservation test with alternating buffers and small changing regions; otherwise unchanged pixels can disappear when a slot does not contain the immediately preceding generation.

## Measured result

On the local Qt 6.11.2 software backend, the probe rendered six distinct 320 × 96 premultiplied RGBA frames both normally and with `WAYLAND_DISPLAY` and `DISPLAY` removed. Each raw frame is 122,880 bytes. The two test passes averaged 0.170 ms and 0.140 ms of polish/sync/render work per frame; the deliberate 40 ms animation wait and PNG encoding are excluded. `file` confirmed the diagnostic output is 320 × 96 8-bit RGBA PNG. These measurements establish feasibility only; production benchmarks must include shared-memory publication, trusted texture upload, input round trips, multiple concurrent surfaces, cgroup limits, and sustained frame pacing.

The first run also inherited a GTK platform-theme selection that attempted to open display `:0` despite `QT_QPA_PLATFORM=offscreen`. Setting `QT_QPA_PLATFORMTHEME=none` removed that dependency. The production worker must use an environment allowlist that selects the offscreen platform, software backend, neutral platform theme, and full-frame update mode rather than inheriting the user's Qt environment.

Software rendering is a boundary proof, not full QML compatibility: Qt's software adaptation does not render `ShaderEffect` or particle effects and has different transformed-text behavior. Schema v2 must report that limitation honestly until a restricted GPU worker is available. The reference work cannot claim to preserve the full arbitrary-QML visual surface merely because ordinary rectangles, text, canvas-like raster content, alpha, and animations render successfully.

## Required trusted bridge

The Omarchy shell cannot efficiently ingest a continuously changing external RGBA buffer through existing QML alone. The first implementation therefore needs a small trusted Qt QML module loaded into the existing Quickshell process. It should expose a `QQuickItem` that:

- receives only a daemon-authenticated surface handle over the separate `omarchy-plugin-host`-to-bridge session;
- maps host-created read-only frame slots and uploads the validated current slot into a scene-graph texture;
- clips rendering and input to its assigned geometry;
- reports size, DPR, visibility, focus, and bounded input events to the daemon, which validates and relays worker-directed events over FD 5;
- preserves the last valid frame on malformed input or worker failure;
- never parses plugin manifests, evaluates plugin QML, stores grants, opens arbitrary paths, or makes authorization decisions.

The bridge is native code in the trusted process and must be kept substantially smaller than the sandboxed renderer. The `A3` host-module supplement selected an Omarchy-owned public-API Qt module that Quickshell imports dynamically; it does not require a Quickshell fork or upstream extension.

## Evidence required to complete A3

- The probe builds against the installed Qt 6 toolchain.
- Animated QML produces distinct frames through `QQuickRenderControl` and the software backend.
- The same probe succeeds with `WAYLAND_DISPLAY` and `DISPLAY` absent.
- The output has alpha and fixed dimensions suitable for a bar or bounded overlay.
- The measured render time and bytes per frame are recorded.
- The required trusted module boundary is explicit enough for `B4`, `C5`, and `C6` to work independently.
- Every published diagnostic frame is a full frame rather than a partial update applied to a cleared or stale buffer.

## Deferred questions

- Whether the trusted bridge uploads shared-memory pixels on the render thread through a custom `QSGTexture` path or copies through a simpler first-version `QSGSimpleTextureNode` implementation.
- Whether damage rectangles are worth implementing before correctness and bounds tests pass.
- Which frame-rate and resolution limits are safe defaults for each surface role.
- Whether a later restricted render-node and zero-copy transport provides enough latency and power benefit to justify the extra kernel and driver attack surface.
