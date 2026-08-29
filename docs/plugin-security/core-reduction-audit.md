# Secure plugin runtime reduction audit — Batch B

Base commit: `91f11037cdb3e7650481fd7014f9081998284ec3`.

Batch B consolidates policy/grant ownership without changing provider inventory, wire protocol, native bridge, shell integration, packaging, or activation.

## Ownership change

- Replace the persistent revision/grant stores and permission administration CLI with the immutable 33-line `policy::GrantSnapshot` and `policy::Revocation` handoff.
- Keep manifest declaration ceilings, current grants, exact operation/scope checks, immutable plugin/revision/policy/generation binding, grant epochs, and runtime revocation in the broker.
- Replace the persistent filesystem audit database and CLI with an `AuditSink` interface and bounded in-memory implementation. The broker remains fail-stop when the sink rejects a decision.
- Compile the bounded audit implementation into the broker-runtime owner instead of retaining a separate audit production library.
- Defer grant decision persistence, candidate/update state, rollback state, durable audit storage/export/migration, and administrator tooling beyond the retained interfaces.
- Preserve all seven provider operations present at HEAD, including the existing fake-status test provider. Provider and permission-registry reduction belongs to Batch C and is absent here.

## Exact budgets

| Measure | HEAD 91f11037 | Batch B | Delta |
|---|---:|---:|---:|
| Production C++ | 23,075 | 18,896 | -4,179 |
| Test/support C++ | 14,161 | 12,507 | -1,654 |
| Total native C++ | 37,236 | 31,403 | -5,833 |
| Native C++ files | 165 | 157 | -8 |
| Production libraries/QML modules plus private worker | 20 | 17 | -3 |
| Explicit non-operation wire message types | 28 | 28 | 0 |
| Built-in operation IDs | 7 | 7 | 0 |

The target reduction removes the separate revision-store, grant-store, and audit-store libraries. Audit implementation ownership moves into the existing broker-runtime target, so no replacement wrapper target is added.

LOC uses physical `*.cpp`, `*.h`, and `*.hpp` lines under `native/plugin-runtime`. Test directories, fixtures, test/compatibility executables, fake/probe programs, `channel_peer.cpp`, and proof/vertical-slice code are classified as support.

## Exact boundary

The 21 complete paths and four partial paths are listed in `/tmp/omarchy-plugin-security-batch-b-paths.txt`. The exact tested content for every partial path is in `/tmp/omarchy-plugin-security-batch-b-native.2Dejgc`. The other 147 dirty paths are listed in `/tmp/omarchy-plugin-security-batch-b-excluded-paths.txt` and remain outside this batch.

The four partial paths are the working audit, root CMake graph, and the broker runtime implementation/header. Their tested Batch-B forms deliberately restore the later provider-removal hunks so the seven-operation HEAD provider registry remains unchanged.

## Verification

- Configure: `cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-security-batch-b-native.2Dejgc-build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON` — pass.
- Complete native build: `cmake --build /tmp/omarchy-plugin-security-batch-b-native.2Dejgc-build -j2` — pass, 350/350 steps.
- Focused policy/security tests: `ctest --test-dir /tmp/omarchy-plugin-security-batch-b-native.2Dejgc-build --output-on-failure -R '^(plugin-permission-contract|capability-definition-contract|plugin-broker-core|plugin-audit-store|plugin-dynamic-broker-runtime)$'` — 5/5 pass.
- The consolidated dynamic broker test directly verifies active `GrantSnapshot` revocation, epoch replacement, replay rejection, audit-before-publication, dynamic revocation, and fail-stop behavior from an independently rejecting `AuditSink`.
- A broader name-based run also selected `plugin-qml-broker-api`; its five native policy/broker tests passed and only that display-dependent QML test failed because this restricted namespace has no display.

## Proposed commit

`Consolidate plugin grant and audit policy`

This checkpoint performs no installation or live activation and does not modify bridge, shell, packaging, provider, capability registry, or wire-message behavior.
