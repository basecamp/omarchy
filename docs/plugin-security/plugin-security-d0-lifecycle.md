# D0 Secure Plugin Lifecycle Integration

## Result

D0 adds the trusted schema-v2 lifecycle coordinator under `native/plugin-runtime/lifecycle/` and registers the previously standalone C2 grant store in the aggregate native build. The coordinator composes only C0 pinned discovery, C1 immutable revision storage, and C2 permission state. Its operations map to secure install/update staging, explicit enable, rollback, revocation, recovery, and failed-candidate discard without loading QML or starting a worker.

The existing `omarchy plugin add`, `enable`, `update`, `disable`, and `remove` commands remain the schema-v1 compatibility path. D0 does not silently route their mutable checkout operations through the secure model or describe them as sandboxed. C0's `legacy_v1_unsafe` diagnostic becomes D0's explicit `unsafe_legacy_schema` result and no secure store is changed. Product command/UI switching remains E4/E5 work after D1 can launch an activated revision.

## Closed manifest-to-permission transform

B1 intentionally preserves permission scope objects as canonical opaque JSON, while B2 owns typed grants. D0 is the only transform between those contracts for the initial registry:

| Manifest capability | Accepted canonical scope | B2 scope |
|---|---|---|
| `storage.private` | `{"quotaBytes":N}` | Quota total `N`, item `min(N, 4096)` |
| `notifications.send` | `{"categories":["token",...]}` | Token set |
| `audio.play-cue` | `{"cues":["token",...]}` | Token set |
| `service.fake-status` | `{"operations":["acknowledge","list"],"resourceIds":[N,...]}` | Numeric resource set and the two registered B2 operations |

Capability version is exactly 1. Tokens accept only bounded B2 identifiers composed of ASCII alphanumeric, `.`, `_`, and `-`; numeric resources must be nonzero `uint32_t`; duplicates, escapes, unknown keys/shapes/capabilities/operations, invalid quotas, and any B2-invalid scope fail staging. This transform is versioned by the secure manifest and B2 registries rather than accepting generic scope JSON. The B1 source-request fingerprint and B2 policy-request fingerprint remain distinct and both are bound into activation.

## Lifecycle transactions

`stage` first recovers the stores, requires a trusted directory-to-tree-SHA-256 pin, consumes the one C0 `VerifiedPlugin`, inserts and re-verifies the C1 immutable revision, translates requests, and then creates a C2 candidate. A first install and every added, expanded, incomparable, or requirement-changed request is reported as requiring permission review. The active C1 binding is never changed by staging. Safe unchanged/narrowed grants are inherited only through B2's delta result.

`enable` is an explicit lifecycle action. It requires the exact candidate identity and every required capability to have a granted record, rediscovers the immutable stored tree against its digest, constructs the C1 binding from exact tree/manifest/source/policy/grant identities, commits C1 first, and then promotes the matching C2 candidate. Optional capabilities without a grant remain unavailable; they are never inferred or auto-granted. A permission-expanding update therefore remains a candidate until reviewed and explicitly enabled.

`rollback` commits C1's retained exact binding with a fresh generation and then restores the corresponding retained C2 grant revision with that generation. `revoke` persists the C2 epoch/state reduction first and atomically rebinds the active C1 record to the new grant fingerprint without changing plugin, revision, manifest, source request, policy, generation, or rollback target. The returned B2 revocation action is preserved for D4 to enforce against live work.

## Cross-store recovery

C1 and C2 are independent durable files, so D0 uses one deterministic commit direction instead of pretending they share a filesystem transaction: revision activation/rollback is committed first, while revocation is committed to the grant store first. `recover` compares the complete active C1 tuple against C2 active, candidate, and rollback records and permits only four exact states:

- exact active identity and grant fingerprint: already consistent;
- C1 matches the exact candidate and its fingerprint: finish candidate promotion;
- C1 matches the retained rollback identity and fingerprint, allowing only C1's fresh generation: finish grant rollback;
- C1 matches active identity but its grant fingerprint is stale: finish the grant-only C1 rebind after a persisted revocation.

Every other missing, forged, cross-plugin, source-request, policy, revision, generation, or fingerprint combination fails recovery. C1 continues to validate stored manifest metadata and tree contents. A revision staged before a later grant-store failure is inert and may be pruned; it never becomes active by recovery guesswork.

C2's on-disk schema advances to version 2 to retain one rollback grant revision. The reader accepts the bounded version-1 layout and normalizes it in memory; the next mutation writes version 2 atomically. Activation moves the former active grants to rollback, and rollback swaps only an exact retained revision while applying C1's fresh monotonic generation. The stable JSON/CLI output schema remains version 1 and adds a `rollback` member to plugin records.

## Evidence and handoff

The focused lifecycle suite covers the closed scope transform, pinned first install, explicit review flag, enable denial before a required grant, immutable activation, post-pin source mutation, unchanged-update inheritance without active replacement, recovery between C1 activation and C2 promotion, recovery between C1 rollback and C2 restoration, recovery between C2 revoke and C1 rebind, fresh rollback generation, permission-expansion staging/denial, candidate discard, and explicit schema-v1 unsafe classification. C1 separately tests grant-only rebind constraints, and C2 tests reading the prior empty version-1 binary layout.

Run:

```bash
cmake -S native/plugin-runtime/lifecycle -B build/plugin-lifecycle -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-lifecycle
ctest --test-dir build/plugin-lifecycle --output-on-failure
```

D1 should consume only `RevisionStore::current()` after `LifecycleManager::recover()` succeeds. E4 owns the authenticated permission prompt and calls C2 decisions before explicit enable; D4 consumes the returned revoke action and epoch. E5 owns switching product commands while keeping schema-v1 wording honest. Removal, publisher/source metadata, remote fetch, signature policy, health checks, worker restart, pruning policy, and live broker notification are not fabricated by this storage transaction.
