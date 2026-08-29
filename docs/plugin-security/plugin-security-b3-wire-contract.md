# B3 Wire Contract Foundation

## Result

The first B3 slice promotes the frozen A2 envelope and endpoint state rules into a Qt-free C++20 library under `native/plugin-runtime/contracts/wire/`. It is deliberately a standalone CMake subproject so the contract can be reviewed and tested before the plugin runtime's root build graph and transport are introduced.

This slice is a bounded wire and state contract. It does not read sockets, inspect credentials, own descriptors, launch workers, authorize capabilities, define render identifiers, or select a serialization system for broker operations.

## Production API boundary

`envelope.hpp` defines the exact 40-byte network-order envelope, the three endpoint roles, the common message identifiers, hard per-role payload caps, caller-owned encoding, and a non-owning decoded packet view. Decoding performs no payload allocation or copy. The trusted role is an input supplied by the endpoint binding; the packet's role field cannot select or override it.

`common.hpp` defines fixed-size payload codecs for `HELLO`, `WELCOME`, `NEGOTIATION_FAILED`, `CANCEL_RESULT`, and `PROTOCOL_ERROR`. Each decoder accepts only the exact payload size and a known bounded enum value.

`state.hpp` provides independent trusted-side and worker-side negotiation, a three-role aggregate readiness gate, and a selected-endpoint state machine. Each endpoint negotiates its role version independently, while readiness requires all required roles to report the same nonzero launch generation. Selected traffic is checked against the negotiated payload and in-flight limits.

The operation tracker uses caller-selected compile-time capacity and `std::array`; it never allocates according to a peer-provided correlation or limit. Worker-to-host and host-to-worker requests have separate tables, so the same correlation value may be active in both directions. Cancellation retains a correlation until both its cancel result and exactly one terminal operation result have been observed, including crossed delivery order.

`role_registry.hpp` is the extraction boundary for domain protocols. A registry is a non-owning view over trusted static role schemas. Each schema declares message identifiers, allowed direction, correlation rule, semantic class, payload bounds, and typed-error bounds. The common state machine validates those declarations and uses them to reject unknown, wrong-direction, malformed, stale, unmatched, duplicate, and over-limit traffic before domain dispatch.

`error.hpp` separates fatal endpoint-contract violations from typed recoverable operation outcomes. Transport code may emit a bounded protocol notice only after all B5 transport and identity validation succeeds; this library only returns the disposition and reason.

## Exact ownership boundaries

B3 owns envelope layout, common fixed payload serialization, negotiation order, aggregate readiness, correlation/cancellation state, and the role-schema registry interface.

B5 must compose this library with fixed endpoint buffers, `recvmsg`, ancillary quarantine, credential validation, pidfd-backed launch identity, descriptor cardinality and ownership, teardown ordering, and packet direction. None of those mechanisms is represented by a fake boolean or spike transport abstraction here.

B4 owns render/input message identifiers and payloads, surface and frame generations, slot identifiers, memfd schemas, and bridge integration. This slice contains no render domain identifiers.

B2 owns capability, grant, gesture, scope, audit, and broker-handle semantics. Those values never enter the common header or common state machine.

B2 and B3 must jointly freeze the broker operation identifier space and bounded payload serialization before broker role schemas can be registered. B2 owns the capability and grant vocabulary; B3 will own the corresponding broker request, response, typed-error, and event wire definitions. This slice does not choose Protobuf, invent placeholder production operations, or imply that arbitrary serialized bytes are safe. The role registry can accept the eventual generated or static schema table without changing the outer envelope and correlation implementation.

B6 owns the promoted shared corpus and fakes. The literal common-message goldens currently live with this standalone contract test so this slice remains independently verifiable; B6 may consume the literals from a single shared fixture without duplicating ownership.

## Memory and trust properties

- Encoding writes into a caller-owned span and fails before writing when the header, endpoint role, payload cap, or output size is invalid.
- Decoding returns a span into the caller-owned packet and validates the fixed header, trusted endpoint role, hard cap, and exact datagram length before exposing the payload.
- The decoder performs length comparison without addition on the untrusted length field.
- Negotiation uses fixed payload arrays and selects only the highest mutually supported nonzero role version.
- A worker cannot produce a second valid `HELLO` from one negotiator, and either side becomes failed after invalid negotiation state.
- The selected state uses fixed-capacity linear tables. The negotiated in-flight value may narrow but never widen the compiled capacity.
- Fatal state errors poison the selected endpoint state so a caller cannot continue dispatch after desynchronization.
- Payload views and schema registry views are non-owning. Their backing packet and static schema data must outlive the call or state object respectively.

## Verification

The focused executable checks exact literal bytes for all seven common message types, cap and cap-plus-one behavior for every role, malformed fixed fields and lengths, trusted role binding, independent overlap and no-overlap negotiation on all roles, aggregate same-generation readiness, direction-scoped correlations, cancellation races, typed terminal errors, fixed in-flight exhaustion, unknown role messages, and fatal versus recoverable classification.

Run the standalone checks with:

```bash
cmake -S native/plugin-runtime/contracts/wire -B /tmp/omarchy-b3-wire-build -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-b3-wire-build -j2
ctest --test-dir /tmp/omarchy-b3-wire-build --output-on-failure
```

Run undefined-behavior and address sanitizers with:

```bash
cmake -S native/plugin-runtime/contracts/wire -B /tmp/omarchy-b3-wire-sanitize -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build /tmp/omarchy-b3-wire-sanitize -j2
ctest --test-dir /tmp/omarchy-b3-wire-sanitize --output-on-failure
```

Root CMake integration, transport integration, shared fuzzing, and disposable-VM acceptance remain later graph nodes and are intentionally not part of this disjoint slice.
