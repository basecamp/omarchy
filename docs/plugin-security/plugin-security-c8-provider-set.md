# C8 Initial Provider Set and Schemas

## Result

C8 adds a closed, production-facing provider adapter set under `native/plugin-runtime/providers/` for the representative `storage.private@1`, `notifications.send@1`, `audio.play-cue@1`, and `service.fake-status@1` capabilities. It consumes B2's operation, scope, activation, and grant types and C4's fixed provider registry. It does not accept a capability name, plugin identity, host path, command, URL, device, descriptor, or environment value from provider payload bytes.

The set is deliberately an adapter boundary rather than an ambient service client. Storage, notification, and audio effects require trusted callbacks installed by the host before the worker starts. Those callbacks are already bound to the plugin's private store or the named host facility and receive only validated domain values. The fake status provider is an in-process deterministic service with host-seeded resource/status records. D4 owns attaching concrete host callbacks, driving asynchronous completions, returning C4 terminal packets, and appending C3 audit events.

## Defense in depth

Every callback receives C4's `AuthorizedRequest`, but the provider set independently requires the exact constructor-supplied `ActivationBinding` and current nonzero grant epoch before parsing or producing a side effect. This is not a substitute for B2 authorization; it prevents a stale or incorrectly routed authorized request from crossing a provider boundary. `revoke` accepts only a strictly newer epoch, updates the matching provider epoch, and marks every pending fake-service list for that capability cancelled. Notification and audio are synchronous `deny_new` operations. Storage operations are synchronous in this initial set, so there is no storage work to cancel after the callback returns.

Provider input and output spans are non-owning and never retained. The fake provider copies status text into fixed arrays and retains only correlation, epoch, and numeric resource for pending work. Explicit cancellation and revocation both suppress completion, completion is single-use, an undersized result span leaves the pending result available for a trusted retry, and an unknown correlation has no effect. Correlation is coherence metadata under the already authenticated C4 channel, not an authenticator.

## Exact version 1 provider schemas

All integers are unsigned network byte order. All lengths must exactly consume the provider payload; trailing bytes, reserved values, zero identifiers, overlong fields, embedded NUL, invalid UTF-8, UTF-8 surrogates, overlong encodings, and disallowed control characters fail the provider call without invoking a backend.

| Operation | Input | Output | Additional domain rule |
|---|---|---|---|
| `storage_read` / `storage_remove` | `u16 key_bytes`, key | Read: `u8 found`, three zero bytes, `u32 value_bytes`, value. Remove: empty. | Key is 1–64 ASCII alphanumeric, `.`, `_`, or `-`, but not `.` or `..`. Read value is at most 4096 bytes and the authorized item quota. |
| `storage_write` | `u16 key_bytes`, `u32 value_bytes`, key, value | Empty | Value is at most 4096 bytes and the authorized item quota. Demand cannot exceed the callback's host-configured total/item ceiling. |
| `notification_send` | `u16 title_bytes`, `u16 body_bytes`, title, body | Empty | Only the already-authorized exact `timer` category is registered. Title is 1–96 bytes; body is 1–512 bytes. Newline is allowed only in body. |
| `audio_play_cue` | Empty | Empty | Only the already-authorized exact `complete` cue is registered. The callback never receives a path or arbitrary cue. |
| `fake_status_list` | Empty | Asynchronous: `u16 count`, zero `u16`, then `u32 id`, `u8 acknowledged`, zero `u8`, `u16 text_bytes`, zero `u16`, text per record. | Demand must contain exactly one nonzero resource and only the list operation. At most 16 host-seeded records, each with 1–160 bytes of text. |
| `fake_status_acknowledge` | `u32 status_id` | Empty | Demand must contain exactly one nonzero resource and only the acknowledge operation. The status must already exist under that resource. |

Storage callbacks must themselves implement the declared private-store contract: operate relative to the already-open revision-private store, reject links and non-regular objects, make writes atomic, and enforce aggregate quota across concurrent calls. C8 constrains what can reach that callback and caps each transfer, but it does not claim that an arbitrary callback implementation is safe. No callback is provided by default, so an unintegrated provider fails closed.

## Test evidence

The provider tests use memory-only trusted callbacks and no session resources. They cover all seven registered operations, literal request/result vectors, exact length and reserved layouts, output truncation, key traversal syntax, per-item and callback authority ceilings, activation mismatch, stale/revoked epochs, unregistered notification category and audio data, invalid/control/overlong UTF-8, resource/status confusion, duplicate status identities, unknown completion, explicit cancellation, revocation cancellation, and single-use completion.

Run the component with:

```bash
cmake -S native/plugin-runtime/providers -B build/plugin-providers -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-providers
ctest --test-dir build/plugin-providers --output-on-failure
```

For the bounded sanitizer pass:

```bash
cmake -S native/plugin-runtime/providers -B build/plugin-providers-sanitize -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build/plugin-providers-sanitize
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir build/plugin-providers-sanitize --output-on-failure
```

## D4 handoff

D4 should own the `ProviderSet` for exactly the lifetime of its C4 core, register the returned fixed registry, and install callbacks only after opening and validating trusted resources. It must pass C4's accepted revocation epoch to `ProviderSet::revoke` before delivering any provider completion, map `CompletionResult` to the exact C4 terminal/cancel state, and audit only authoritative identity/scope/result metadata rather than title, body, key, value, or status text. D4 must reject startup if a granted production capability lacks its callback instead of silently registering a no-op success.

The concrete storage callback and desktop notification/audio transports remain integration work. They must not spawn a shell, accept plugin-controlled argv or paths, inherit ambient descriptors, or connect to an unrestricted session bus. A future provider/schema version is required for additional categories, cues, resources, fields, or larger bounds; version 1 has no generic extension map or fallback operation.
