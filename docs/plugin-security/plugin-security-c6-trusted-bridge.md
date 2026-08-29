# C6 trusted remote-surface bridge

## Result

C6 provides the narrow trusted Qt/QML endpoint for a sandbox-rendered plugin. `RemotePluginSurface` is a QML-creatable `QQuickPaintedItem` that receives only B4 `TrustedAllocation` records and private, already-validated pixel spans through `TrustedFrameSink`. It copies each accepted full frame into a host-owned `QImage` before returning to the producer and paints only that copy.

This preserves arbitrary-QML visual expressiveness without loading plugin QML into the trusted shell engine. A worker may render ordinary QML scenes, animations, transparent overlays, drawers, or roaming desktop characters; the trusted shell composes their bounded RGBA surfaces as pixels. The bridge never imports the plugin's source, QML types, JavaScript, shaders, metadata, filesystem paths, or commands.

## Trust boundary

The inbound interface is exactly B4's `TrustedFrameSink`:

- `configure` accepts one internally consistent, daemon-selected allocation and activates one surface generation. A second configuration is a terminal lifecycle failure.
- `present` accepts only the active surface key, a strictly increasing nonzero frame sequence, and exactly `frame_bytes` trusted pixels. Invalid, stale, or replayed frames do not replace the last valid image.
- The producer's memory is never retained. The bridge constructs and validates a `QImage`, takes a deep copy, and only then publishes the new frame to Qt Quick.
- `clear`, destruction, disconnect, or a transport failure remove all visible pixels and focus state. Once a terminal failure destroys the surface state, a later frame cannot resurrect it.

The `TrustedFrameSink` caller is trusted code after B4's untrusted-publication copy/recheck. C6 never accepts a worker memfd, mapping, descriptor, shared-memory header, or raw envelope. D2 must not bypass the B4 consumer or invoke the item from an IPC thread; delivery is serialized onto the item's Qt GUI thread.

The outbound interface is intentionally narrower than a broker. `AuthenticatedInputTransport` serializes only B4 `InputEvent` and `FocusEvent` values, validates each constructed packet with B3's selected render-role state, and fixes the endpoint role, role version, launch generation, zero correlation, flags, payload length, message type, and direction. `RemotePluginSurface` applies the per-surface B4 input and focus gates before transport, so stale surfaces, invalid fields, out-of-bounds coordinates, unfocused transitions, zero sequences, and replays never reach the sink.

`RenderPacketSink` is the synchronous adapter supplied by a previously credential-authenticated and negotiated D1 render session. It must encode or copy the payload before `send` returns. Its shared ownership keeps both the session adapter and transport alive while the QML item is bound. B5/D1 remain responsible for the socket, peer credentials, outer envelope encoding, descriptor cardinality, process lifetime, and write/backpressure policy; the C6 type name does not claim to perform peer authentication itself.

No manifest, grant, permission, policy, broker provider, plugin identity string, or free-form inspection value crosses this component. Permission decisions remain authoritative in B2/C4 and are not represented in the QML API.

## Lifecycle, focus, and inspection

The item mirrors B4's `allocated -> active -> suspended -> active -> destroying -> destroyed` state machine. Suspended or destroying surfaces reject frames and input. Suspending clears host focus; resuming does not restore focus implicitly. D3 must send explicit monotonic focus transitions around compositor focus changes and owns input queue limits, transition-preserving coalescing, and rate policy.

QML can inspect only bounded host-generated properties: connection state, whether a valid frame exists, focus state, surface id/generation, last accepted frame sequence, and one of the fixed strings `ready`, `disconnected`, `invalid-allocation`, `invalid-lifecycle`, `stale-frame`, `invalid-pixels`, `input-rejected`, or `transport-failed`. Inspection never includes attacker-supplied text or payload bytes.

Nonterminal malformed, stale, and replayed frame failures preserve the last valid pixels for continuity and record a fixed inspection state. Invalid allocation, duplicate configuration, explicit disconnect, and transport failure are terminal and clear pixels and focus. Input rejection does not modify focus or send a packet.

## Executable evidence

The standalone CMake target builds the generated `Omarchy.PluginHost` QML module and a fake-producer test without C5. The test proves:

- a fake `TrustedFrameSink` producer can configure and publish a valid surface;
- producer memory mutation after `present` cannot change the owned QImage;
- malformed, replayed, and stale-generation frames preserve the last valid image;
- suspend blocks input and disconnect clears pixels and focus;
- focus and input use exact B3/B4 render message types, version, generation, flags, payload length, zero correlation, direction, and network-order codecs;
- stale focus and repeated input sequences never reach the packet sink;
- a failed sink terminates the transport and prevents visual resurrection;
- zero launch generation, a missing session sink, invalid allocation, and duplicate configuration fail closed.

Focused commands:

```bash
cmake -S native/plugin-runtime/trusted-bridge -B /tmp/omarchy-c6-build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-c6-build
ctest --test-dir /tmp/omarchy-c6-build --output-on-failure
```

The same suite must pass a Release build and an ASan/UBSan build. The installed-package QML import, live C5/B4 publication path, scene-graph performance, real input conversion/coalescing, compositor focus integration, transparent overlay behavior, worker crash/restart, and disposable-VM visual proof remain D2, D3, E1, F2, and F5 work.
