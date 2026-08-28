# D2 Worker-to-Host Render Integration

## Result

D2 joins the C5 arbitrary-QML renderer, B4 bounded shared-frame transport, and C6 trusted QML bridge through `HostRenderSession`. The trusted host owns the surface allocation, sealed-size two-slot memfd, frame consumer, selected render-role protocol state, and final copied pixels. The worker receives one duplicate writable descriptor for `SURFACE_ALLOCATE`; the bridge receives only the consumer's private validated byte copy.

The integration remains a standalone subproject so it does not collide with the shared native runtime CMake graph. The host-daemon adapter can consume this library in the dedicated integration pass. D3 still owns surface placement, input queue/coalescing policy, focus routing, and inspection UI.

## Session contract

The host starts from a nonzero launch generation and an internally consistent B4 allocation whose surface generation matches it. It creates `HostFrameRegion` and `FrameConsumer`, configures one `TrustedFrameSink`, and drives the selected B3 render endpoint through these phases:

1. Send correlated software `PROFILE_OFFER`.
2. Require the exact correlated software `PROFILE_SELECT` terminal.
3. Send correlated `SURFACE_ALLOCATE` with exactly one duplicate frame-region descriptor.
4. Require `SURFACE_ALLOCATED` for the exact host-owned surface key.
5. Accept only uncorrelated `FRAME_READY` messages while active.

All inbound packets are bounded by the render endpoint cap and decoded as exact 40-byte B3 envelopes before role-state processing. Wrong direction, role, version, launch generation, request correlation, payload length, message order, or message type terminates the session. The packet sender is synchronous: it must finish its `sendmsg` or duplicate the descriptor before returning. The session closes its duplicate after every send, and the caller retains ownership of descriptors passed into the launcher API.

The B5 launcher now exposes `send_with_descriptors` with an exact zero-or-one descriptor bound. Plain `send` is the zero-descriptor form. Invalid and excess descriptors fail before `sendmsg`; a successful call never consumes the caller's descriptor. The worker receives passed descriptors with `MSG_CMSG_CLOEXEC`. Launcher receive now admits B3's legal maximum broker datagram of 40 + 65,536 bytes. It also scans and closes every delivered `SCM_RIGHTS` descriptor before returning `MSG_CTRUNC`, preventing the truncated-control leak found during D1 review.

## Frame safety and lifecycle

For each `FRAME_READY`, `FrameConsumer` copies only the host-owned allocation extent, validates the fixed header and allocation identity, checks even publication sequence ordering before and after the copy, and retains a private candidate. Only an accepted candidate is deep-copied again into C6's host-owned `QImage`. The bridge now restores the host allocation's device-pixel ratio on that owned image; the first D2 integration run exposed that C6's prior deep copy silently reset DPR to 1.

The reference software profile remains full-frame-only, so there is no plugin-selected damage region. The animated integration test alternates both slots for 121 complete frames with the partial-update optimization disabled, which proves that alpha and unchanged pixels survive buffer alternation without trusting damage metadata. Damage rectangles remain unavailable until a later profile adds a separately bounded and preservation-tested contract.

Replayed or stale frame/slot sequences are rejected without replacing the last valid bridge image. Malformed envelopes, above-cap datagrams, malformed shared headers, allocation mismatches, ambiguous lifecycle packets, descriptor-send failure, consumer safety failures, bridge rejection, and explicit peer loss disconnect the sink, unmap the frame region, discard the consumer, and clear visible pixels. A failed or disconnected session cannot resume. Resize or DPR changes require a fresh generation/session and fresh bridge item; D3 must not mutate an active allocation in place.

## Evidence

The D2 test loads the real C5 expressive QML fixture, negotiates the real B4 payloads, transfers the real sealed-size memfd descriptor, publishes through the two-slot frame protocol, consumes through `FrameConsumer`, and presents through the real C6 `RemotePluginSurface`. It verifies animated frames, premultiplied alpha, 1× and 2× DPR, logical-versus-pixel sizing, stale-frame preservation, malformed shared headers, malformed and oversized envelopes, peer loss, descriptor transport failure, and terminal pixel clearing.

The local Qt 6.11 software run published and deep-copied 121 frames of 64 × 32 RGBA (991,232 bytes total) in approximately 254 ms wall time while deliberately waiting 2 ms per animation sample. The measured maximum trusted consumer-plus-bridge copy was below 10 µs in repeated runs. These values are feasibility evidence, not production budgets; D2 records them and asserts only a conservative 5-second total and 50-millisecond maximum copy to catch catastrophic regressions on CI.

Focused validation commands:

```bash
cmake -S native/plugin-runtime/render-session -B /tmp/omarchy-d2-build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-d2-build
ctest --test-dir /tmp/omarchy-d2-build -R plugin-render-session --output-on-failure
```

The same session test must pass with `PLUGIN_SECURITY_RENDER_SESSION_SANITIZERS=ON`. Launcher contract, malicious-peer, and real-Bubblewrap tests cover zero/one/excess host descriptor sends, caller ownership, worker close-on-exec receipt, maximum broker datagrams, and `MSG_CTRUNC` descriptor cleanup.

## Deferred integration

- Add `render-session` and `trusted-bridge` to the shared root native CMake graph in the dedicated conflict-free integration commit.
- Bind `PacketSender` to the authenticated D1 `launcher::Worker`; the new one-descriptor launcher method is the required `SURFACE_ALLOCATE` seam.
- Let C3/D4 own pidfd supervision, health deadlines, restart policy, lifecycle activation, and rollback outcomes around session failure.
- Let D3 own compositor geometry, input/focus routing and bounds, queue limits, coalescing, and inspection presentation.
- Validate installed Quickshell texture upload, multiple simultaneous surfaces, worker process crash/restart, and graphical fidelity in E1/F2/F5.
