# B4 Render, Surface, Input, and Bridge Contract

## Status

`B4` implements and tests the contract consumed later by the sandboxed QML worker, trusted plugin daemon, and Quickshell bridge. The contract is intentionally Qt-free. It proves trusted allocation, bounded shared-memory access, cooperative publication detection, surface generations, input clipping, explicit software-profile limitations, and a narrow bridge interface without claiming that the live worker-to-daemon-to-Quickshell path exists yet.

The implementation lives under `native/plugin-runtime/contracts/surface/` and builds as a standalone C++20 CMake subproject. `B0` may include it through an optional subdirectory without making `B4` own the root native build. `B3` owns the common outer envelope and registers the role-level rules exported here. `B5` owns authenticated descriptor receipt and process identity. `B6` owns the eventual shared literal fixture and fuzz corpora.

## Version 1 software profile

The only reference profile in this node is `software_rgba8888_full_frame_v1`:

- Qt is offscreen with the software scene graph, but those environment and application-lifecycle mechanics remain `B5` and `C5` work.
- Pixels are premultiplied RGBA8888 with exactly four bytes per pixel.
- Logical and pixel dimensions are each between 1 and 4,096. Width, height, stride, frame length, slot extent, mapping length, and every conversion to `size_t` or `off_t` use checked arithmetic.
- One frame is at most 64 MiB. Version 1 publishes complete transparent-cleared frames and has no partial-damage payload.
- The device-pixel ratio is a nonzero host-chosen rational. Pixel dimensions must equal the ceiling of logical dimensions multiplied by that rational.
- `ShaderEffect`, particles, GPU rendering, and partial damage are explicitly unsupported. Negotiation fails when version 1 is not offered; the runtime must not silently run an incompatible plugin with degraded visuals.

This is an intentionally incomplete arbitrary-QML profile. It preserves the architecture needed for a future restricted-GPU profile without pretending the software renderer covers every existing plugin.

## Host-created shared region

The daemon creates one anonymous memfd for each surface generation. Its size is fixed before it crosses a trust boundary. It carries `F_SEAL_GROW`, `F_SEAL_SHRINK`, and `F_SEAL_SEAL`, but not `F_SEAL_WRITE`, because the worker must retain a writable mapping. The daemon's mapping is changed to `PROT_READ` before a close-on-exec duplicate is handed to the worker.

`HostFrameRegion` reconstructs the expected allocation using the system page size before allocating. It rejects an internally inconsistent trusted record rather than feeding unchecked values to `ftruncate` or `mmap`. `FrameConsumer`, `SurfaceState`, and `InputGate` also use validated factories, so no caller can trigger allocation or state construction from an unchecked `uint64_t` frame length. The worker descriptor is a caller-owned close-on-exec implementation handle for the authenticated FD 5 allocation message; B5 wraps that ownership before dispatch, and the descriptor is never exposed to plugin QML as a path or general integer-FD API.

The region contains two equal slots:

```text
mapping
  slot 0 at 0
    128-byte header
    zero/reserved bytes through offset 4095
    fixed-capacity full-frame pixels at offset 4096
  slot 1 at align_up(4096 + frame_bytes, page_size)
    same layout
```

The mapping size is exactly twice the slot extent. The allocation record, not worker-written memory, owns surface identity, generation, logical and pixel geometry, DPR, stride, pixel format, frame length, system page size, slot offsets, and total capacity.

## Slot header

The 128-byte header is fixed-width. The sequence word is native-endian shared atomic storage because Omarchy ships one same-architecture native package; all other integers are network byte order so captured headers remain reviewable. Allocation requires a page/slot alignment of at least eight bytes, the runtime rejects a misaligned mapping before forming a typed pointer, and `initialize_frame_mapping` starts the two `uint64_t` object lifetimes before the daemon changes its mapping to read-only or the worker attaches. Version 1 is explicitly a Linux same-architecture shared-memory ABI, not portable file serialization.

| Offset | Size | Field | Rule |
|-------:|-----:|-------|------|
| 0 | 8 | slot sequence | Native-endian lock-free atomic; nonzero even means published, odd means being written |
| 8 | 8 | frame sequence | Nonzero and strictly increasing per surface generation |
| 16 | 8 | surface id | Nonzero host-issued value |
| 24 | 8 | surface generation | Nonzero host-issued value, separate from launch generation |
| 32 | 4 | profile version | Exactly 1 |
| 36 | 4 | header size | Exactly 128 |
| 40 | 8 | logical width and height | Must match trusted allocation |
| 48 | 8 | pixel width and height | Must match trusted allocation |
| 56 | 8 | DPR numerator and denominator | Both nonzero and must match trusted allocation |
| 64 | 4 | stride | Exactly pixel width times four |
| 68 | 4 | pixel format | Premultiplied RGBA8888 |
| 72 | 4 | damage count | Exactly zero in version 1 |
| 76 | 4 | reserved | Zero |
| 80 | 8 | payload length | Exactly the trusted full-frame length |
| 88 | 40 | reserved | Zero |

The implementation decodes only a bounded 128-byte local header copy. Header fields never select a mapping, slot, allocation, pointer, or copy length.

## Publication and consumption

The worker publishes into one of two slots:

1. Store the preceding odd sequence value with release ordering.
2. Write the fixed header fields and the complete frame.
3. Execute a release fence and store the announced nonzero even sequence.
4. Send an authenticated `FRAME_READY` notification containing only surface id, surface generation, slot index, exact slot sequence, and global frame sequence. It carries no descriptor.

The trusted consumer validates the notification against its allocation, rejects a non-increasing per-slot sequence, acquire-loads the exact even sequence, copies header bytes 8 through 127 without non-atomically reading the live sequence word, rechecks the sequence, validates every header field, copies exactly the trusted preallocated frame length into private memory, and rechecks the sequence again. A scoped guard rejects reentrant consumption before any shared consumer state is touched; the per-call no-throw observer exists only to make hostile publication timing deterministic and is never retained. A changed or odd sequence drops the candidate and preserves the last valid private frame. Slot reuse never blocks the producer; a slow consumer observes a changed sequence and drops that frame. Sequence or frame-sequence wrap therefore fails closed and requires a new surface generation.

This protocol detects a cooperative overlapping write and rejects notification-level sequence reuse. It does not authenticate pixels and cannot prevent a malicious worker from changing pixels without changing the sequence or performing an ABA sequence change entirely between trusted loads. Such a worker can create a visually torn or adversarial frame, but it cannot change trusted geometry, make the daemon read outside the fixed mapping, alias worker memory into Quickshell, or replace the last private frame with an invalidly bounded buffer. If atomic visual snapshots ever become a security property, a later protocol needs ownership transfer rather than a stronger seqlock claim.

## Surface lifecycle

Surface ids and generations are nonzero daemon-issued values scoped to the authenticated daemon/bridge session. A surface moves through:

```text
Allocated -> Active <-> Suspended -> Destroying -> Destroyed
```

Only `Active` accepts frames. Only an `Active`, focused, exact-generation surface accepts focus-sensitive input. Resize, DPR, or profile changes create a new allocation and increment the surface generation; old notifications and mappings become stale immediately. The new generation starts without a valid frame, so the bridge does not relabel old pixels under new geometry.

## FD 5 role messages

`render_messages.hpp` owns a disjoint `uint16_t` version-1 numeric range and exports B3 `MessageRule` values directly. `PROFILE_OFFER` and `SURFACE_ALLOCATE` are correlated host-to-worker requests with exact 24-byte and 96-byte payloads; `PROFILE_SELECT` and `SURFACE_ALLOCATED` are their worker-to-host terminal responses with exact 8-byte and 16-byte payloads. A denial uses the common exact 24-byte render `TYPED_ERROR`. Release, suspend, resume, input, and focus are zero-correlation one-way host messages because trusted state changes before notification and never waits for a worker acknowledgement. `FRAME_READY` is a zero-correlation worker event.

Every payload has a fixed network-order codec with exact length, bounded enums, and reserved-zero checks: allocation is 96 bytes, lifecycle/surface keys are 16, frame-ready is 40, input is 56, and focus is 32. A typed error may name only `PROFILE_OFFER` with a zero surface or `SURFACE_ALLOCATE` with the exact nonzero surface; it cannot turn an event or one-way message into an implied request.

The role schema composes directly with B3's `RoleSchemaRegistryView` and `SelectedEndpointState`. B3 deliberately binds an in-flight entry only to its correlation id and direction, so the trusted render endpoint must also pass every admitted render request through the fixed-capacity `RenderRequestTable`. Before asking B3 to retire a terminal, it validates the exact pair `PROFILE_OFFER -> PROFILE_SELECT` with no surface, `SURFACE_ALLOCATE -> SURFACE_ALLOCATED` with the same surface, or a typed error naming the recorded request and surface. Only after B3 accepts the terminal does the endpoint complete the B4 table entry. A mismatch does not consume either table entry and is fatal to the session. Integration tests prove crossed terminals, wrong surfaces, and wrong-request errors fail while an exact pair retires both B3 and B4 state.

`SURFACE_ALLOCATE` requires exactly one host-created descriptor. Every other version-1 render message requires zero descriptors, and no worker-originated descriptor type exists. B3 intentionally does not own descriptor counts, so B4 exports a parallel exact-cardinality lookup that B5 applies while the descriptor remains quarantined.

The type rules do not parse the common envelope or authorize a peer. `B3` performs outer parsing and state validation; `B5` retains quarantined descriptor ownership until both layers accept the message and allocation schema.

## Bounded input

Every input event carries the exact surface id/generation and a nonzero host-monotonic sequence. `InputGate` rejects a repeated or decreasing sequence per surface generation. Focus uses a separately named monotonic focus sequence, so coalescing pointer motion cannot consume a focus transition number. Coordinates are unsigned Q16.16 values strictly inside trusted logical geometry. Deltas are signed Q16.16 values whose magnitude cannot exceed the corresponding surface dimension, including safe handling of `INT32_MIN`.

Unknown input kinds fail closed. Every kind rejects nonzero fields it does not own; pointer button/state, scroll axis/phase, key code/state, touch id/state, and touch cardinality are bounded. Keyboard, pointer-button, and touch transitions require trusted focus; motion can be accepted unfocused for later host policy to coalesce. Version 1 does not expose IME composition, clipboard, drag and drop, accessibility, global shortcuts, synthetic input, or lock-screen input.

Queue sizes, rate budgets, transition-preserving coalescing, and termination behavior belong to `C6`/`D3`. Those implementations must not turn an overflow into attacker-controlled allocation.

## Trusted bridge boundary

The bridge sees only `TrustedFrameSink` and `HostInputSource`:

- `configure(allocation)` receives daemon-owned geometry and capacity.
- `present(surface, frame_sequence, trusted_pixels)` receives a private bounded copy, never a worker mapping or descriptor.
- `clear(surface)` and `disconnect()` remove stale presentation state.
- `submit(input)` carries already host-derived, clipped event data for daemon validation.

The interface has no plugin manifest, grant, filesystem path, command, QML component, raw worker descriptor, or broker-provider method. `C5` can implement the QML renderer against a fake host, and `C6` can implement the `QQuickItem` bridge against a fake trusted frame producer. Their first live composition remains `D2`.

## Executable evidence

The standalone suite currently proves:

- checked add, multiply, align, cast, minimum/maximum geometry, DPR, stride, frame, slot, and mapping calculations;
- exact network-order header fields, reserved-zero enforcement, round trip, and allocation matching;
- real memfd creation, fixed-size seals, close-on-exec worker duplication, writable worker mapping, read-only host mapping, publication, and private copy;
- alternating-slot full-frame publication, global and per-slot replay denial, deterministic mutation after header and pixel copies, stale-generation denial, last-valid-frame preservation, and bounded malicious or ABA-capable pixels;
- lifecycle transition and focus gates;
- Q16.16 coordinate/delta edges, unknown-kind denial, key/button/touch limits, monotonic input replay denial, and stale input denial;
- exact codecs for every render payload plus B3 schema validation, exact request-type/surface pairing, crossed-terminal denial, and correlated request/terminal integration;
- explicit software-profile rejection instead of silent downgrade; and
- the Qt-free bridge call/data boundary.

Run it with:

```bash
cmake -S native/plugin-runtime/contracts/surface -B build/plugin-surface -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-surface
ctest --test-dir build/plugin-surface --output-on-failure
```

The tests carry `render`, `unit`, `property`, `protocol`, `integration`, and `adversarial` labels. Strict GCC and Clang ASan/UBSan runs pass; LeakSanitizer is disabled only in the managed ptrace environment and remains part of an ordinary runner. Literal shared render fixtures, live descriptor quarantine, long malicious cross-process mutation campaigns, frame-copy budgets, packaged ABI proof, and visual compositor evidence remain owned by `B6`, `D2`, `F1`, `F4`, and `F5`.
