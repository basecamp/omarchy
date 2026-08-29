# A2 Common Outer-Envelope Freeze

## Purpose

This document freezes the common packet envelope shared by the schema-v2 worker's control, broker RPC, and render/input endpoints. It resolves the prototype ambiguity in which a `HELLO` marked protocol version 1 offered protocol version 1, defines the fields that trusted code must inspect before role-payload allocation, and leaves domain schemas to `B1`–`B6`.

The envelope is not an authorization token. The supervisor-created endpoint binding remains authoritative for plugin id, revision, worker role, launch generation, PID identity, and endpoint role. Header fields echo and correlate that trusted state so stale, swapped, or malformed traffic can be rejected before dispatch.

## Version model

Version 1 separates two concepts:

- **Envelope version** defines the fixed header layout and framing rules needed to parse `HELLO`, `WELCOME`, and all later packets. Every packet described here has envelope version 1.
- **Role protocol version** defines the payload schemas and state machine for one endpoint role. It is zero during `HELLO`, selected by `WELCOME`, and fixed to the selected nonzero version afterward.

A worker therefore sends an envelope-v1 `HELLO` with role protocol version zero and a fixed negotiation payload containing its supported role-version range. It does not use role protocol v1 to negotiate role protocol v1.

Envelope compatibility is intentionally not self-negotiated through an unknown envelope. If the magic, envelope version, or header size is unsupported, the receiver closes the endpoint without interpreting later fields or sending a response whose framing the peer may not understand. Host, worker, protocol library, and bridge ship atomically, so an envelope mismatch indicates a stale or substituted artifact rather than an ecosystem compatibility case.

Role compatibility is negotiated independently on FD 3, FD 4, and FD 5. This permits a later package to retain an older broker role protocol while adding a render protocol, without weakening the fixed outer parser.

## Fixed header

Every multi-byte integer uses network byte order. The version-1 header is exactly 40 bytes.

| Offset | Size | Field | Version-1 rule |
|-------:|-----:|-------|----------------|
| 0 | 4 | `magic` | ASCII `OMPL`, value `0x4f4d504c` |
| 4 | 2 | `envelope_version` | Exactly 1 |
| 6 | 2 | `header_size` | Exactly 40 |
| 8 | 2 | `endpoint_role` | 1 control, 2 broker RPC, 3 render/input |
| 10 | 2 | `message_type` | Common handshake/error type or a type defined by the selected role protocol |
| 12 | 2 | `role_protocol_version` | Zero only during negotiation; selected nonzero version afterward |
| 14 | 2 | `flags` | Zero in envelope version 1 |
| 16 | 4 | `payload_length` | Exact bytes following the 40-byte header and no more than the bound endpoint cap |
| 20 | 4 | `reserved` | Zero in envelope version 1 |
| 24 | 8 | `launch_generation` | Zero in worker `HELLO`; supervisor-assigned nonzero generation in `WELCOME` and every post-selection packet |
| 32 | 8 | `correlation_id` | Zero for uncorrelated handshake/events; nonzero for requests, replies, errors, and cancellation |

The fixed header contains no plugin id, revision digest, capability, grant, surface identity, path, pointer, or payload offset. Those values either belong to the trusted endpoint/launch record or to bounded role schemas.

### Why launch generation is fixed-header state

All three endpoint pairs belong to one supervisor-created launch tuple. Including the 64-bit launch generation in the fixed header lets each receiver reject packets from a stale worker generation before payload allocation and lets fakes exercise cross-channel stale traffic using the common parser.

The generation does not establish identity. A worker can write any number into a packet; the trusted receiver compares it with the launch record bound to that endpoint. The worker sends zero in its first `HELLO` because it has not selected a session. The supervisor returns its authoritative nonzero generation in each `WELCOME`. Every later packet in both directions repeats exactly that generation.

Generation values are never reused within a daemon lifetime. After daemon restart, private endpoint replacement remains the primary isolation boundary; the implementation should seed or persist the generation counter so an accidentally retained trusted-side packet cannot match the new session. The exact counter persistence mechanism belongs to the supervisor contract.

### Why correlation is fixed-header state

`correlation_id` is the common replacement for a role-specific `request_id`. Trusted code needs it before decoding a role payload to enforce in-flight bounds, route a response, reject reuse, and process cancellation without allocating an operation-specific object.

Correlation ids are scoped by launch generation, endpoint role, and initiating direction. The same numeric value may exist independently on two endpoint roles, but it cannot identify an operation across roles. An initiator chooses a nonzero 64-bit id and must not reuse it while the operation remains in flight. A response, typed error, cancellation, or cancellation result repeats the target operation's id.

There is no separate cancellation-request id in envelope version 1. Cancellation is an idempotent operation on the target correlation id. The receiver returns one of the role protocol's bounded outcomes, such as accepted, already completed, not cancellable, or unknown. The original operation still produces exactly one terminal result: success, typed failure, or cancelled. Role contracts define the race rule when a result and cancellation cross.

Unsolicited events, frame-ready notifications, input events, readiness transitions, and one-way shutdown notices use correlation id zero unless their role schema explicitly defines a request/reply exchange. Domain sequence numbers such as frame sequence, surface generation, grant revision, or audit sequence remain inside their role schemas; the launch generation is not a substitute for domain ordering.

## Endpoint roles and bounds

The trusted receiver knows the expected role from the FD-to-launch binding before reading a packet. It compares the header role with that binding and treats a mismatch as fatal. Payload bytes never select an endpoint role.

| Worker FD | Endpoint role | Maximum payload | Maximum packet | Version-1 descriptor rule |
|----------:|---------------|----------------:|---------------:|---------------------------|
| 3 | Control | 4,096 bytes | 4,136 bytes | `SCM_RIGHTS` always forbidden |
| 4 | Broker RPC | 65,536 bytes | 65,576 bytes | `SCM_RIGHTS` forbidden; use broker-owned opaque handles |
| 5 | Render/input | 16,384 bytes | 16,424 bytes | At most one descriptor, only on an explicitly descriptor-bearing host-to-worker message |

The broker cap accommodates bounded structured service results while requiring pagination or broker-owned blob handles for HTTP bodies, files, images, logs, and other bulk data. The render cap accommodates bounded surface/input metadata; pixel bytes remain in host-created shared memory. The control cap keeps lifecycle traffic small and independent of data-plane pressure.

Each endpoint uses one fixed receive buffer sized to its maximum packet and `recvmsg(..., MSG_TRUNC | MSG_CMSG_CLOEXEC)`. Every endpoint reserves a fixed ancillary quarantine area for one `SCM_CREDENTIALS` record and up to four delivered `SCM_RIGHTS` descriptors even when its role permits none. This quarantine capacity is not permission to use four descriptors: control and broker still permit zero, and render permits at most one on a typed host-to-worker message. It exists so unexpected descriptors can be found and closed reliably. If ancillary data exceeds the quarantine, `MSG_CTRUNC` is fatal; Linux closes descriptors discarded by ancillary truncation, and the receiver closes every descriptor that was delivered into the visible quarantine.

The initial render profile passes one host-created memfd containing the negotiated fixed-capacity slots. Worker-to-host descriptor transfer is forbidden. A later role protocol may add a different descriptor count only by defining a new render role version and preserving a hard pre-receive ancillary cap.

## Asymmetric credential validation

PID and user namespaces make `SCM_CREDENTIALS` intentionally asymmetric. The trusted daemon and sandbox worker do not apply the same authority rule.

### Trusted daemon receiving from a worker

The daemon is outside the worker's Bubblewrap PID and user namespaces. Kernel credentials are translated into the daemon's namespace, where the worker has its outer PID and mapped host UID/GID. Every worker packet must contain exactly one `SCM_CREDENTIALS` record whose PID, UID, and GID match the supervisor's launch binding. The daemon compares the numeric outer PID with the PID recorded when it forked/launched the worker and uses the retained pidfd to prove that record still names the same live process rather than a reused PID.

This is a strict authority check. A packet from a forked descendant, a process that received an endpoint, or a different sandbox has a different outer PID and is rejected even if its payload, UID, generation, and endpoint role are correct.

### Worker receiving from the trusted daemon

The daemon is outside the worker's child PID namespace and generally has no PID representation there. Linux may therefore translate the daemon PID in `SCM_CREDENTIALS` and `SO_PEERCRED` to zero. Requiring the worker to observe the daemon's outside numeric PID would reject the legitimate peer and would falsely describe a namespace-translated value as an authority check.

At startup, the worker reads `SO_PEERCRED` from each already inherited endpoint after entering its final namespaces and records the kernel-translated PID/UID/GID tuple as a consistency baseline. For each received packet it requires exactly one `SCM_CREDENTIALS` record, requires the translated UID and GID to match the baseline, and applies this PID rule:

- if the baseline PID is nonzero, the per-packet PID must equal it;
- if the baseline PID is zero because the outside daemon is not visible, the per-packet PID must also be zero; and
- the worker never substitutes a payload PID, host PID, namespace PID, or guessed value for the kernel-translated tuple.

This worker-side rule is defense in depth against inconsistent or accidentally substituted peers. It is not an authorization root: PID zero is not a daemon identity, and multiple processes outside the child PID namespace can translate to zero. Worker provenance comes from receiving the unnamed endpoint only through the supervisor-controlled FD 3/4/5 launch, then completing the role and launch-generation handshake. The trusted daemon's outer-PID/pidfd check remains the authoritative sender-identity enforcement.

## Common message types and negotiation

Message type values `0x0001` through `0x00ff` are reserved for the common envelope state machine. Role-specific types begin at `0x0100` and are interpreted only after role negotiation.

| Type | Name | Direction | Header requirements |
|-----:|------|-----------|---------------------|
| `0x0001` | `HELLO` | Worker to trusted endpoint | Role version 0, generation 0, correlation 0, no descriptors |
| `0x0002` | `WELCOME` | Trusted endpoint to worker | Selected role version, authoritative nonzero generation, correlation 0, no descriptors |
| `0x0003` | `NEGOTIATION_FAILED` | Trusted endpoint to worker | Role version 0, generation 0, correlation 0, then close |
| `0x0004` | `TYPED_ERROR` | Either direction after selection | Selected role version, bound generation, nonzero correlation matching the failed request |
| `0x0005` | `CANCEL` | Either direction after selection | Selected role version, bound generation, nonzero correlation naming the target operation |
| `0x0006` | `CANCEL_RESULT` | Receiver of `CANCEL` to initiator | Selected role version, bound generation, same nonzero correlation |
| `0x0007` | `PROTOCOL_ERROR` | Optional best-effort notice before fatal close | Use only after the full outer header and peer credentials were validated |

The `HELLO` payload is a fixed four-byte structure: `minimum_role_version` and `maximum_role_version` as two unsigned 16-bit network-order integers. Both must be nonzero and minimum must not exceed maximum. The worker advertises a contiguous supported range for that endpoint role.

The trusted endpoint selects the highest mutually supported role version. `WELCOME` carries the selection in `role_protocol_version` and has an eight-byte payload: `maximum_payload` and `maximum_in_flight`, each an unsigned 32-bit network-order integer. Both must be nonzero. The advertised payload limit may be narrower than the endpoint's hard cap but can never widen it. The in-flight limit applies independently to requests initiated in each direction.

If there is no overlap, the trusted endpoint may send `NEGOTIATION_FAILED` using envelope version 1, then closes. Its six-byte payload contains `reason`, `minimum_role_version`, and `maximum_role_version` as unsigned 16-bit network-order integers. Version 1 defines reason 1 as no common role version. It never falls back to a role version outside both ranges.

`CANCEL` has no payload; its header correlation id names the target. `CANCEL_RESULT` has a two-byte network-order outcome enum: 1 accepted, 2 already completed, 3 unknown, or 4 not cancellable. `PROTOCOL_ERROR` has only a two-byte bounded reason enum and no attacker-controlled detail. `TYPED_ERROR` payloads are role-version schemas because operation failures and safe redaction differ by role.

Each endpoint negotiates independently, but the supervisor does not declare the worker ready until every endpoint required by its declared worker role has returned `WELCOME` with the same launch generation. In the initial QML worker profile, FD 3, FD 4, and FD 5 are all required. A missing, duplicated, role-swapped, or second `HELLO` is fatal for that endpoint and fails worker readiness.

Optional features do not use ignored flag bits. A feature that changes parsing, bounds, descriptors, or semantics requires a new role protocol version. A compatible optional operation can be advertised inside the selected role schema and denied as unsupported without changing the outer envelope.

## Validation order

A receiver performs these checks in order before role-payload allocation or dispatch:

1. Receive into the fixed buffer and fixed ancillary area for the endpoint's trusted role binding.
2. Walk all visible ancillary records immediately. Copy the one credential record into value storage and place every delivered descriptor into close-on-destruction quarantine ownership before any branch can return, send an error, or close the endpoint.
3. Mark `MSG_TRUNC`, `MSG_CTRUNC`, empty packets, packets shorter than 40 bytes, duplicate/malformed credentials, malformed ancillary records, and excess descriptors as fatal. Before acting on the error, close every quarantined descriptor. Descriptors discarded by kernel ancillary truncation are already closed by the kernel.
4. Apply the asymmetric credential rule: the daemon strictly matches the worker's outer PID/UID/GID and pidfd-backed launch record; the worker checks the inherited endpoint's namespace-translated `SO_PEERCRED` consistency baseline and permits translated PID zero only as described above.
5. Validate magic, envelope version, header size, flags, reserved field, and exact packet length.
6. Require header endpoint role to equal the role assigned to that FD.
7. Enforce the endpoint payload cap, direction, message type, and descriptor policy before interpreting the role payload.
8. Enforce handshake state, role protocol version, and launch generation.
9. Enforce common correlation rules and the endpoint's maximum in-flight count.
10. Validate any permitted descriptor's message-specific type, size, seals, access mode, surface, generation, and lifetime while it remains quarantined.
11. Only after every envelope, credential, role, schema, and descriptor check succeeds may dispatch take ownership of a permitted descriptor or receive the bounded payload.

The implementation uses an RAII quarantine or a single cleanup block so no validation or error path can leak a received FD. `MSG_CMSG_CLOEXEC` prevents an injected descriptor from surviving an intervening `exec`, but close-on-exec is not cleanup and does not replace an explicit close.

## Fatal and recoverable errors

### Fatal endpoint errors

The receiver closes the affected endpoint on any condition that makes framing, peer identity, role binding, or state ambiguous:

- invalid magic, envelope version, header size, flags, or reserved field;
- truncated packet or ancillary data, packet-length mismatch, or endpoint-cap violation;
- missing, duplicate, malformed, or unexpected kernel credentials;
- at the daemon, credentials that do not match the worker's outer PID/UID/GID and pidfd-backed launch binding;
- at the worker, credentials inconsistent with the inherited endpoint's translated `SO_PEERCRED` baseline, except for the explicitly permitted PID-zero translation;
- endpoint-role mismatch or descriptor-policy violation;
- non-`HELLO` first packet, invalid version range, duplicate `HELLO`, or message before `WELCOME`;
- unsupported or changed role protocol version after selection;
- zero or mismatched launch generation after selection;
- unknown message type for the selected role version;
- correlation id zero where the message requires one, illegal reuse while in flight, or a response from the wrong initiating direction; and
- role-payload corruption that prevents the decoder from determining operation boundaries or safe recovery.

On every failure, the receiver closes all quarantined descriptors before sending an error or closing the endpoint. If the full envelope, credentials, generation, role, and descriptor count are valid, the receiver may send one bounded `PROTOCOL_ERROR` before closing. It must not attempt this for an unparseable envelope, must not include attacker-controlled payload text, and must not wait for delivery before teardown. Supervisor policy decides whether loss of one endpoint terminates the worker; control loss always does, while broker or render loss may first enter a bounded degraded transition.

### Typed recoverable errors

A valid request with a known schema and correlation id receives a typed error without closing the endpoint when the failure is isolated to that operation:

- capability undeclared, ungranted, revoked, or outside scope;
- gesture missing or expired;
- well-formed argument invalid for the selected operation;
- provider unavailable, busy, timed out, or rate limited;
- opaque handle unknown, stale, expired, or wrong for that operation;
- resource not found or state conflict;
- cancellation accepted, already completed, unknown, or unsupported; and
- optional operation unsupported within the negotiated role version.

Typed errors use bounded enums and redacted fields defined by the role schema. They do not echo arbitrary attacker strings, secrets, paths, provider diagnostics, or payload fragments. Repeated recoverable violations remain subject to endpoint rate limits and may trigger supervisor termination as abuse, but one denied operation does not desynchronize the channel.

## Cross-channel semantics

The three channels have independent packet order, correlation namespaces, backpressure, and role protocol versions. The common launch generation proves only that they belong to the same supervised worker launch; it does not impose a total order across channels.

Cross-channel state is reconciled against authoritative trusted state:

- a revoke updates the grant authority before any notification, so broker requests are denied regardless of whether the worker has processed a control event;
- surface destruction updates trusted surface state before notification, so a later queued frame for that surface is rejected by its role-level surface generation;
- shutdown and forced termination use supervisor state and pidfd control, not successful delivery of a control packet;
- bridge reconnect creates new trusted bridge/surface generations without changing the worker launch generation unless the supervisor restarts the worker; and
- audit order uses trusted audit sequence/timestamps, not correlation ids or arrival order across endpoints.

Role schemas must carry the smallest domain generation or sequence needed for their own stale-state checks. They must not infer authorization or causal order from launch generation alone.

## Envelope spike evidence boundary

The standalone C++20 fixture in `experiments/plugin-security/channel/envelope/` exercises this frozen contract without depending on Qt or a role-schema implementation. It proves the 40-byte network-order layout with exact complete-packet goldens, per-endpoint cap boundaries, independent HELLO/WELCOME negotiation, worker-side WELCOME validation, and an aggregate readiness gate that rejects mixed launch generations across control, broker, and render/input.

Its correlation model keeps separate operation tables for each initiating direction. The fixture admits the same numeric correlation id in opposite directions, consumes matching RESPONSE and TYPED_ERROR terminal messages, correlates CANCEL_RESULT in the reverse direction, retains an accepted cancellation until exactly one terminal result arrives, and prevents reuse while that result remains outstanding. Unknown message types, unmatched or duplicate terminal messages, stale generations, duplicate HELLO, selected traffic before WELCOME, and maximum-in-flight overflow are fatal test cases.

The descriptor fixture uses an aligned fixed ancillary quarantine, scans every visible ancillary record before deciding, and transfers ownership only after the complete render message and sealed read-only memfd schema validate. Descriptor-bearing render messages require exactly one descriptor; zero, excess, wrong-direction, wrong-schema, malformed-envelope, and ancillary-truncation cases are fatal. Tests compare the exact bounded open-FD set before and after rejection and record cleanup, bounded error-notice, and teardown events in that order. The event recorder models the production ordering seam; the spike does not send a real protocol error or own a production endpoint supervisor.

Identity checks in this fixture deliberately split proof responsibilities. The daemon-side model requires exact outer PID/UID/GID equality with a launch binding and invokes a retained-pidfd validation hook. The worker-side model records an actual `SO_PEERCRED` baseline and tests both ordinary nonzero PID matching and the translated-PID-zero rule with stable UID/GID. The separate Bubblewrap identity spike supplies the production-shaped PID/user namespace observation and pidfd exit evidence; this same-process envelope fixture does not claim to reproduce namespace translation by itself.

This is bounded protocol evidence, not the production B3/B5 library. Role schemas still own surface identifiers, slot geometry, role-specific typed errors, domain generations, and resource lifetimes, and production acceptance must compose those validators before descriptor transfer or dispatch.

## Inputs to Wave 1

The common envelope is narrow enough for every Wave 1 lane to consume without sharing domain implementations:

- `B1` uses launch generation and fixed negotiation fixtures in lifecycle state transitions, but keeps revision and manifest identity out of the header.
- `B2` uses correlation and generation in grant/audit fixtures, while capability and handle schemas remain payload definitions.
- `B3` owns the common encoder/decoder, endpoint state machines, request/cancellation tables, typed errors, and role protocol registries.
- `B4` defines render/input message types, surface/frame generations, memfd allocation messages, and the live slot protocol within the render cap.
- `B5` maps control, broker, and render endpoints to FDs 3, 4, and 5; applies descriptor allowlists and RAII cleanup; and supplies the daemon's outer-PID/pidfd launch binding plus the worker's translated-credential baseline.
- `B6` owns golden 40-byte headers, handshake peers, malformed packets, role swaps, stale generations, correlation races, descriptor injection/cleanup, namespace-translated credential cases, cap boundaries, and version-overlap fixtures.

Required shared fixtures include exact golden bytes for every common message, one version-overlap and one no-overlap exchange per role, packets at and one byte above every endpoint cap, correlation reuse/cancel/result races, stale launch generations on all three endpoints, endpoint-role swaps, strict outer worker PID/pidfd matching at the daemon, legitimate translated daemon PID zero at the worker, inconsistent translated credentials, and forbidden descriptors. Descriptor-injection fixtures record the receiver's open-FD set before and after every fatal path and prove that unexpected, malformed, excess, and schema-rejected descriptors are closed before an error is sent or the endpoint is torn down.

## Freeze summary

- Envelope version 1 is a fixed 40-byte parser contract; role protocol versions are negotiated inside it.
- Launch generation and correlation id are fixed-header fields because they gate stale traffic, in-flight bounds, responses, and cancellation before role decoding.
- Plugin identity, revision, grants, surfaces, handles, and domain sequence numbers are not header fields.
- FD 3 control caps payloads at 4 KiB and forbids descriptors; FD 4 broker caps at 64 KiB and forbids descriptors; FD 5 render/input caps at 16 KiB and permits at most one explicitly typed host-created descriptor.
- Endpoint role is bound by the supervisor and echoed in the header; a mismatch is fatal.
- The daemon strictly authenticates the worker's outer PID through its launch record and pidfd; the worker only checks namespace-translated credentials for consistency on its inherited endpoint and accepts legitimate PID-zero translation without treating it as authority.
- Every delivered descriptor enters close-on-error quarantine immediately and is closed before any error response or teardown unless full validation explicitly transfers ownership.
- Envelope/framing/identity/state ambiguity is fatal; known operation denial or failure is a typed recoverable error.
- Cancellation uses the target operation's correlation id and produces one terminal operation outcome.
- Cross-channel ordering uses authoritative state plus role-specific generations, never launch generation alone.
