# C4 Authenticated Broker Core

## Result

C4 implements a Qt-free, fixed-capacity broker core under `native/plugin-runtime/broker/`. It composes the B3 selected-endpoint state with B2's activation-bound permission authority, decodes a closed operation-specific demand, re-authorizes every request against current grants, and dispatches only to a trusted statically registered provider. It does not open a socket, obtain peer credentials, launch a worker, persist grants or audit records, or implement provider-side effects; those boundaries remain C7, D1, C2/C3, and C8 work.

The input is a B3 `PacketView` produced only after D1 decodes an exact `SOCK_SEQPACKET` datagram on the supervisor-created broker endpoint and authenticates that endpoint against the launch tuple. C4 never accepts a plugin id, revision, policy fingerprint, or launch generation from its payload. Its constructor receives the authoritative B2 `ActivationBinding`, and B3 rejects a packet whose envelope generation differs.

## Closed wire schema

Broker role version 1 maps the seven B2 operation ids directly to worker-to-host request message ids. This prevents a payload from selecting an authority different from its envelope message. All requests require a nonzero correlation and contain an exact eight-byte request header:

| Offset | Size | Field | Rule |
|-------:|-----:|-------|------|
| 0 | 2 | repeated operation | Must exactly equal the envelope message id |
| 2 | 2 | demand bytes | Exact operation-specific demand length |
| 4 | 4 | provider bytes | Must equal the remaining datagram length and be at most 60 KiB |

Quota demands are exactly two network-order `uint64_t` values and pass B2's quota validation. Notification categories and audio cues are a nonempty length-prefixed B2 scope token of at most 96 bytes. Fake-service demands are one nonzero resource id plus the repeated exact operation id and reserved-zero bytes. No request syntax can express a command, host path, socket, URL, credential, environment variable, arbitrary capability id, or plugin identity.

The provider payload remains untrusted operation data. C4 bounds it but does not reinterpret it; C8 owns an exact schema and domain validation for each provider. Version 1 forbids descriptors at the D1 transport boundary. A successful provider response uses the generic host-to-worker `0x5000` terminal. The exact eight-byte common typed error repeats the failed operation, a bounded reason, a B2 decision code, and reserved zeros. C4 binds every terminal error to the operation recorded for that correlation, so crossed typed errors are fatal.

## Dispatch order and authority

The trusted call order is:

1. B3 validates role, version, authoritative generation, direction, message type, payload bounds, correlation uniqueness, and in-flight capacity.
2. C4 validates the repeated operation, exact length arithmetic, typed demand, and B2 scope rules.
3. B2 checks the authoritative activation binding, declaration, current grant state and epoch, requested scope, and any trusted single-use gesture.
4. C4 records the exact correlation, operation, capability, grant epoch, and authorization result in a fixed table.
5. Only an allowed request reaches the exact registered provider callback. The callback receives authoritative identity by reference, typed demand, bounded provider bytes, and the grant epoch. There is no generic provider lookup by string and no fallback provider.

Denied, revoked, malformed, unknown, and unavailable operations never call a provider. A provider must copy any input it needs before returning; C8 must not retain the non-owning request or response spans. For a synchronous completion it writes into a caller-owned bounded response span and reports the exact byte count. An asynchronous provider returns `pending` with zero response bytes and becomes the only kind of provider work eligible for cancellation or an in-flight revocation action. Registration rejects every `cancel_inflight` provider without a cancellation callback before it can produce side effects. Unknown provider status values, completed, failed, denied, and unavailable work are never mislabeled as actively cancellable.

The fixed provider registry is copied into the core, so passing a temporary registry cannot create a dangling registry reference. Provider context pointers and the non-owning `PermissionAuthority` are trusted dependencies that must outlive the single-owner core; D1 owns that lifetime and destroys the core before either dependency. A scoped guard rejects provider reentry through dispatch, terminal, cancellation, or revocation before it can mutate wire, permission, or in-flight state. The core is owned by one D1 event-loop thread; cross-thread calls are forbidden rather than made implicitly safe with partial locking.

C4 always asks B3 to validate terminal envelope and correlation state, including when C4 has no matching entry or the domain terminal is malformed. It removes its own pending entry only after both B3 and the exact domain binding accept. When a terminal arrives before `CANCEL_RESULT`, C4 retains a tombstone matching B3 until the cancel result arrives; a duplicate terminal therefore remains a B3-fatal duplicate instead of degrading into an unknown correlation. A denied request can terminate only with its exact recorded B2 decision, while an authorized request can never be relabeled as a permission denial; generic success for a denied request is fatal.

Malformed, crossed, unmatched, duplicate, wrong-role, or stale-generation terminal state poisons the core and requires D1 to close the endpoint. Provider cancellation is called only for an authenticated cancel of existing asynchronous provider work. The first cancel records the provider outcome before invoking the callback, and duplicates return that same outcome without repeating provider side effects. B3 and C4 retain cancellation state through either terminal/cancel-result ordering. An unknown cancel is reported to D1 without inventing a pending entry; D1 may emit the trusted `unknown` cancel result directly.

## Live revocation

`revoke` refuses to run after protocol poison or during a provider callback. It validates that a current non-exhausted grant exists, then invokes B2, which increments the grant epoch and marks the grant revoked before returning. It creates a bounded plan only from exact asynchronous provider entries:

- `deny_new` produces no in-flight action; subsequent dispatch is denied immediately.
- `cancel_inflight` returns the exact correlations for provider/supervisor cancellation.
- `restart_worker` sets a trusted restart flag for C7.

Denied requests are not mislabeled as cancellable provider work. C4 never trusts worker cleanup to complete revocation. D4 will couple this plan to provider cancellation, typed terminal errors, audit records, and C7 restart/teardown.

## Evidence and remaining integration

The focused tests cover role-schema validation, identity/generation rejection, exact payload/envelope operation binding, current-grant allow/deny/revoke decisions, provider allowlisting and temporary-registry lifetime, unavailable-provider denial, exact provider context and response bounds, completed-versus-asynchronous state, idempotent cancellation, both terminal/cancel-result orders, in-flight revocation plans, unmatched/duplicate/crossed terminal fatality, typed-error operation and decision binding, reserved-zero enforcement, malformed-session poisoning, provider reentry denial, and B2 gesture missing/expired/wrong-binding/used/valid/single-consumption behavior. The standalone build also runs the B1, B2, and B3 contract tests.

Run the component with:

```bash
cmake -S native/plugin-runtime/broker -B build/plugin-broker -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-broker
ctest --test-dir build/plugin-broker --output-on-failure
```

C4 is not a claim that schema v2 is enabled or that any real provider is safe. C8 must freeze provider payload/result schemas and fake/private-storage/notification/audio implementations; C3 and D4 must append authoritative redacted audits; C7 and D1 must bind the real socket, peer process, descriptor policy, cancellation, teardown, and revocation plan. Schema v1 remains explicitly unsandboxed and never enters this core.
