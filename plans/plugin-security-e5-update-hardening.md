# E5 schema-v1 honesty and update hardening

## Result

The independently testable slice under `native/plugin-runtime/update-hardening/` sits immediately above D0. It performs pinned C0 discovery, compares the candidate against C1's recovered immutable active revision, and delegates every accepted mutation to D0/C2. It does not install, enable, execute, or grant a plugin by itself.

Schema v1 has one representable posture: `legacy_v1_unsafe_unmigrated`. Its result is always unsuccessful, has no staged lifecycle outcome, and makes both granular-permission and sandbox eligibility false. The diagnostic says directly that the plugin is indivisible arbitrary host code with no secure update path. Calling this slice for schema v1 may initialize empty owner-only stores during recovery, but it cannot create a revision activation, candidate, grant record, permission decision, or sandbox claim.

Schema v2 is described only as a secure candidate. This means it is eligible to proceed through the secure lifecycle; it is not a claim that it has been enabled, sandboxed, or granted authority. The existing feature gate remains in force outside this reference path until the system proof wave passes.

## Update decisions

Every candidate is bound to a caller-supplied lowercase SHA-256 tree pin and rediscovered without execution. The active revision is also rediscovered from C1's immutable store under its exact digest before version comparison.

- A first schema-v2 install is staged through D0 and remains subject to required grants and explicit enable.
- An exact reinstall of the already active tree is an idempotent no-op. It does not advance grant-store mutation state or activation generation.
- A higher numeric `major.minor.patch` version is staged, never activated. D0 still computes the permission delta, so expanded or newly required authority remains pending review.
- A lower version is rejected until approval binds both the exact active digest and exact candidate digest. An approval for a different active or candidate revision is stale and fails closed.
- Different content carrying the same version is treated as a rebuild and requires a distinct exact-revision approval. This prevents a replaced tag or republished version from looking like an ordinary reinstall.
- A plugin-id change is never an update and is rejected before revision or grant staging.
- Versions outside the deliberately narrow numeric `major.minor.patch` ordering grammar are not guessed, lexically sorted, or treated as upgrades. They require a future explicit product policy rather than silently weakening downgrade protection.

Manifest versions remain publisher assertions, not cryptographic chronology. A hostile publisher can label changed content with a larger number; the immutable content pin, same-version rebuild check, permission delta, staged activation, and rollback identity remain the actual security boundaries. Publisher signatures and transparency policy are separate follow-on work.

## Failure and recovery behavior

Candidate preflight does not mutate state. Accepted candidates enter D0, which redoes pinned discovery before copying and uses C1/C2's atomic transaction and recovery behavior. A source change between preflight and staging therefore fails the second pin check. Injected failure after revision copy leaves the active binding unchanged and creates no grant candidate. Downgrade and rebuild approval values cannot authorize a later tree because both revision digests are compared exactly before staging.

This slice intentionally does not switch the existing schema-v1 `omarchy plugin add/update/enable` commands. Those commands must continue displaying their current arbitrary-unsandboxed-code warning until the complete secure launch and permission UX is ready; routing them through this candidate API prematurely would create a false migration claim.

## Evidence

The focused test covers unsafe schema-v1 classification and empty authority state, first-install review, exact reinstall idempotence, staged upgrades, denied and exactly approved downgrades, stale approval rejection, denied and exactly approved same-version rebuilds, plugin-id replacement denial, unchanged active identity throughout every candidate path, and injected post-copy failure recovery.

Run the strict suite:

```bash
cmake -S native/plugin-runtime/update-hardening -B /tmp/omarchy-plugin-e5 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-e5
ctest --test-dir /tmp/omarchy-plugin-e5 --output-on-failure
```

For the bounded sanitizer pass, add `-DPLUGIN_SECURITY_UPDATE_SANITIZERS=ON`; C0-C2 retain their own isolated sanitizer suites. The current C2 reference store deliberately places a bounded but large fixed state object on the stack, so the instrumented vertical-slice binary needs a 32 MiB test stack (`ulimit -s 32768`) while that implementation remains in use. Leak detection may be disabled only when the managed ptrace environment prevents LeakSanitizer operation.
