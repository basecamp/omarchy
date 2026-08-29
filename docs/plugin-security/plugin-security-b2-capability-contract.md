# B2 capability, grant, and audit contract

## Outcome

B2 provides a dependency-free C++20 permission-policy contract for the first reference slice. It is independently configurable under `native/plugin-runtime/contracts/permissions`, uses B1's audited SHA-256 implementation for domain-separated fingerprints, and allocates no collection from attacker-controlled counts. It defines policy data and decisions only: B3 owns broker payload schemas and C2/C3 will own durable grant and audit storage.

The registry is closed. An unknown capability version or operation is denied. There is no generic command, filesystem, process, D-Bus, Wayland, network, socket, or arbitrary-path capability. `HttpScope` is a bounded typed scope available for a future reviewed capability, but no HTTP capability or broker operation is registered in this slice. Unix sockets are rejected even by that dormant scope type.

## Frozen registry and broker seam

Capability identifiers are lowercase canonical identifiers paired with a nonzero API version. Broker operation identifiers are stable unsigned 16-bit values. B2 owns these semantic identifiers; B3 will map them to bounded role-specific request, response, event, and typed-error payload schemas without placing capability data in the common 40-byte envelope.

| Capability key | Operation id | Operation | Scope | Gesture | Live revocation |
|----------------|--------------|-----------|-------|---------|-----------------|
| `storage.private@1` | `0x0101` | `storage_read` | total and per-item byte quota, at most 1 GiB | none | deny new and cancel in-flight |
| `storage.private@1` | `0x0102` | `storage_write` | total and per-item byte quota, at most 1 GiB | none | deny new and cancel in-flight |
| `storage.private@1` | `0x0103` | `storage_remove` | total and per-item byte quota, at most 1 GiB | none | deny new and cancel in-flight |
| `notifications.send@1` | `0x0201` | `notification_send` | nonempty, bounded set of registered notification categories | none | deny new |
| `audio.play-cue@1` | `0x0301` | `audio_play_cue` | nonempty, bounded set of registered cue names | none | deny new |
| `service.fake-status@1` | `0x0401` | `fake_status_list` | bounded resource ids and exact operation | fresh trusted single-use gesture | deny new and cancel in-flight |
| `service.fake-status@1` | `0x0402` | `fake_status_acknowledge` | bounded resource ids and exact operation | fresh trusted single-use gesture | deny new and cancel in-flight |

The fake service is intentionally not an ambient executable adapter. Its identifiers represent typed provider operations that C8 can implement against fake data. B3 must preserve these numeric identifiers in its broker-role schema registry or introduce a reviewed adapter with an explicit compatibility test.

## Bounded scope algebra

Every registry entry selects one scope variant. A scope is either equal, narrower, expanded, or incomparable relative to another scope of the same type.

- Quotas compare both total and per-item limits. Moving those dimensions in opposite directions is incomparable.
- Token scopes are sorted sets of at most 16 tokens, each at most 96 bytes.
- Resource scopes contain at most 32 numeric resource ids and 16 operation ids. An operation demand must name exactly the operation being authorized.
- The dormant HTTP type bounds schemes to 4, hosts to 16, methods to 8, and ports to 16. Redirect, loopback, and Unix-socket access are separate expansion dimensions; Unix sockets are invalid.
- Different variants are incomparable. Empty or malformed scopes are rejected before a decision.

Canonical encodings are binary, length-prefixed, big-endian, ordered by the fixed-set implementation, and domain-separated before hashing. The policy request fingerprint sorts requests by capability key, so manifest ordering is not policy identity. Its frozen golden is `878c1ce13a505e4084ed8f5babb0afca1a4850227a5ba17d1c391490f935b286`. This is deliberately distinct from B1's source-request fingerprint: B1 hashes the canonical opaque manifest declaration; B2 hashes the validated semantic policy.

## Decisions, grants, and updates

A manifest request is never a grant. A user decision record binds its monotonic sequence to plugin id, immutable revision, B1 source-request fingerprint, B2 policy-request fingerprint, exact capability version, requested scope, decided scope, actor class, decision, and wall time. A grant may narrow a publisher request but may not expand it. A denial records the exact requested scope so the record cannot misrepresent what the user rejected. Only a trusted UI, interactive CLI, or separately reviewed policy may be recorded as the actor; unattended install acceptance is not a permission actor.

Grant records contain exact capability version, bounded scope, state, and a nonzero revocation epoch. Their domain-separated fingerprint binds plugin, revision, policy fingerprint, and a sorted grant set. The frozen grant golden is `b5e153eed88c957910b10a5c6efb1773210417591c8bd26e321e4aa7abd7e4bf`.

Update inheritance is deliberately asymmetric:

| Change | Inherit prior decision? |
|--------|--------------------------|
| Identical scope and requiredness | Yes |
| Narrower request | A granted record is inherited only when the new request is still inside the old granted scope, and its inherited scope becomes the new scope; denial or revocation may remain denied |
| Expanded or incomparable scope | No |
| Added or removed capability | No |
| Required/optional change | No |
| Capability API-version change | Old version is removed and new version is added; no inheritance |

The delta engine validates both old and new requests and verifies that every old grant was declared and no broader than its request before considering inheritance. A failed candidate therefore cannot smuggle corrupt old authority into a new activation.

## Per-operation authority and revocation

The authority is constructed only when the supervisor's plugin, revision, policy fingerprint, and nonzero launch generation exactly match the validated request set. Every operation resolves through the closed registry and then checks channel activation identity, declaration, grant state, scope, and gesture rule. Missing data, unknown operations, invalid demands, and mismatches return explicit deny codes.

Gesture-bound operations consume a trusted proof once. The proof has a nonzero opaque id and binds plugin, generation, surface, exact operation, and monotonic expiry. The worker's presentation of bytes is not itself proof: the eventual broker must look up a host-issued gesture record and pass that authoritative record to this contract.

Revocation increments the capability epoch and changes its state before returning. New operations are denied immediately. In-flight cancellation or worker restart is selected by the registry's revocation mode and remains a C4/C7 implementation responsibility. Epoch exhaustion fails closed.

Handles are opaque nonzero 128-bit ids. The trusted table validates issuance and binds each handle to plugin, revision, policy fingerprint, generation, one operation, bounded scope, grant epoch, and monotonic expiry. Resolution distinguishes plugin, revision, policy, generation, operation, epoch, expiry, and scope failures; epoch changes invalidate live handles without trusting worker cleanup. Tables have compile-time capacity and reject duplicates or overflow.

## Authoritative redacted audit

Workers cannot append audit records. A trusted lifecycle manager, supervisor, broker, or surface host supplies the producer identity. Records contain only bounded enums, canonical plugin and revision identity, generation, numeric correlation, optional registered operation and capability, decision code, timestamps, and up to eight nonnegative metrics from a closed list. They contain no command line, path, URL, token, content, response body, free-form reason, or worker-supplied log string.

Validation rejects unknown enums, unknown or mismatched operation/capability pairs, duplicate metrics, negative values, and malformed identity. The reference ring has fixed capacity and deterministic oldest-first overwrite behavior. Durable retention, access control, export, and inspection belong to C3. The frozen audit-record golden is `ae35a454833ed2ff344fa510a931237b3b977d6213058f90ce6af4984a2a4161`.

## Representative migration mapping

This first registry is deliberately smaller than the ecosystem's needs. Unimplemented mappings remain denied rather than falling back to ambient host access.

| Current plugin behavior | Secure form in this slice | Remaining work |
|-------------------------|---------------------------|----------------|
| Pomodoro persists timer settings or history | `storage.private@1` with an explicit quota | C8 private-store provider and QML SDK binding |
| Pomodoro raises completion notifications | `notifications.send@1` scoped to a registered `timer` category | C8 notification provider and category registration |
| Pomodoro plays a completion sound | `audio.play-cue@1` scoped to a registered `complete` cue | C8 named-audio provider; no arbitrary media path |
| Basecamp-like fixture lists or acknowledges fake notifications | `service.fake-status@1` with selected fake account/resource ids and exact list or acknowledge operation | C8 fake provider and B3 payload schema; real credentials and Basecamp access remain denied |
| Journal reads or writes private plugin state | `storage.private@1` | User-owned documents require a future persistent file-handle portal and remain denied |
| Service plugin sends HTTP, uses a loopback API, or opens a URL | Denied | Separate reviewed HTTP and gesture-bound open-URI capabilities; no generic network grant |
| 1Password, password-manager, or authenticated CLI integration | Denied | Broker-owned credential handles and purpose-built provider adapters; secrets must not enter audit |
| TOTP/OCR captures the screen, reads selection, or inserts text | Denied | Trusted capture, selection, and focused-input portals with explicit gesture and preview rules |
| Docker, proxy, media, device, compositor, or shell-suite control | Denied | Narrow registered adapters and named actions; never Docker sockets, arbitrary D-Bus, compositor IPC, or commands |

B2 does not embed permission UI or QML. C2 may render these definitions and scopes through trusted surfaces, but it must not reinterpret or broaden them.

## Tests and downstream contract inputs

The standalone target compiles with C++20, `-Wall -Wextra -Wpedantic -Werror`, and optional AddressSanitizer/UndefinedBehaviorSanitizer. Tests cover collection bounds, registry ids, generic-authority absence, scope equality/narrowing/expansion/incomparability, Unix-socket rejection, canonical request and grant fingerprints, order independence, duplicate rejection, decision narrowing, every update-delta class used by the reference requests, activation binding, declaration and grant failures, resource/operation confusion, single-use gestures, live revocation, handle identity/epoch/expiry/scope checks, audit validation, bounded retention, and frozen goldens.

Downstream owners consume these seams:

- C2 persists validated decision and grant records, atomically advances epochs, and presents exact update deltas.
- C3 assigns durable audit sequence/timestamps and stores only validated records under a bounded retention policy.
- C4 calls `authorize` after B3 channel authentication and before provider dispatch, and implements the registry's in-flight revocation action.
- C8 implements only the registered operation schemas and providers.
- B3 keeps capability data out of the outer envelope and binds its operation schema table to the numeric ids above.

## Deferred policy choices

- The manifest-v2 adapter from B1's opaque canonical permission bytes into this typed request set is not yet frozen.
- Real HTTP host-pattern grammar, DNS rebinding behavior, redirect policy, response limits, and loopback UX require a separate reviewed capability version.
- Persistent file handles, credential handles, open URI, clipboard, selection, input, capture, shell events, named compositor actions, and authenticated service adapters require closed registries and threat reviews of their own.
- Grant-store transaction format, source/publisher identity binding, decision signing, audit retention/export, and crash recovery belong to C2/C3.
- Gesture lifetime and which mutations require gestures need usability measurement; the binding and single-use invariant are frozen.
- Cancellation versus worker restart for future capability families is chosen per registry entry, not by the plugin.
- Combination-risk policy and UX, such as sensitive input plus an output channel, remain mandatory before those families can ship.
- Resource-id issuance, persistence, and human-readable trusted labels are provider responsibilities; worker-chosen labels are never policy identity.
