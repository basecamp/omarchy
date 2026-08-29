# D4 audited broker runtime integration

## Result

The integration under `native/plugin-runtime/broker-runtime/` composes C4's broker state machine, C8's bounded providers, C2's immutable activation/grant binding and ephemeral handles, and C3's authoritative audit store. It is a trusted in-process boundary: callers supply the active `RevisionGrants`, provider backend callbacks, and an owner-only audit store; the runtime overwrites every provider identity and epoch field from the active grant snapshot before any provider can be registered.

The component does not invent a second permission model. C4 remains the request and cancellation protocol authority, C2 remains the operation/scope/epoch authority, C8 remains the provider-schema and effect boundary, and C3 remains the only durable audit writer.

## Audit-before-effect gate

The runtime wraps every C8 registry entry with a trusted gate. An authorized request is recorded as a redacted `operation_decided/allowed` audit draft before the underlying provider callback is invoked. If recovery or append fails, the runtime is poisoned and the provider callback is not called. Provider payloads, storage keys and values, notification text, and response bodies cannot enter the audit type; only the registered identity, operation, capability, decision, correlation, and bounded byte-count metrics are emitted.

A synchronous or asynchronous provider failure receives a failed decision record. Protocol terminals receive an allowed, cancelled, or failed record using the decision retained when C4 admitted the correlation. Asynchronous result bytes are first produced into a fixed trusted scratch buffer, durably audited, and only then copied to the caller. A post-effect audit failure cannot undo an already completed external effect, so it poisons the runtime and requires supervisor teardown; the security invariant is specifically that authorization and admission audit precede every provider effect.

Transport-invalid frames that do not contain a valid registered operation and nonzero correlation cannot be represented by B2's operation audit schema. They remain channel-fatal C4/C7 evidence rather than being converted into invented identities or free-form audit text.

## Revocation, cancellation, and handles

The runtime accepts only an active-target C2 revocation whose capability is registered, state is revoked, action matches the static capability definition, and epoch is exactly the live epoch plus one. It durably records the capability revocation before mutating C4, verifies C4 returned that exact epoch and restart action, records every in-flight cancellation before changing C8 provider state, and then updates the local immutable snapshot. A stale, replayed, forged, skipped-epoch, wrong-action, or candidate-target result is rejected without provider mutation.

Handles are issued only for a currently tracked authorized correlation and bind the exact plugin, revision, policy fingerprint, generation, operation, scope, grant epoch, and expiry. Handle issue and denial use the closed C2 audit events. Resolution requires a fresh caller correlation for exact denial attribution. A revocation makes existing handles stale immediately. Handle tables are deliberately memory-only; reconstructing the runtime from a recovered revoked grant snapshot starts with no handles, so restart cannot resurrect authority.

Cancellation and terminal transitions remain C4-owned. The wrapper records cancellation before invoking a provider cancel callback and records accepted terminal state before releasing its correlation tracking. Malformed or mismatched transitions with a known correlation receive a failed audit record and poison through the underlying C4 state machine.

## Evidence

The focused integration test proves durable admission is visible from inside the storage callback, denied notifications never invoke their backend, forged handles fail closed, exact-epoch revocation stales issued handles, replayed revocation is rejected, recovered revoked state cannot perform storage effects or restore handles, and TSV export contains neither storage values nor notification text. It also changes the audit directory to an unsafe mode after construction and proves an admission append failure prevents the provider effect and poisons the runtime.

Run the strict standalone suite:

```bash
cmake -S native/plugin-runtime/broker-runtime -B /tmp/omarchy-plugin-d4 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-d4
ctest --test-dir /tmp/omarchy-plugin-d4 --output-on-failure
```

Run the bounded sanitizer suite with `-DPLUGIN_SECURITY_BROKER_RUNTIME_SANITIZERS=ON`. The native aggregate build includes C3 and D4 when their prerequisite targets are present.
