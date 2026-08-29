# F3 lifecycle, rollback, revocation, and crash proof

## Result

The secure-v2 lifecycle now has a durable non-launchable state. Disable writes that state before worker teardown. Remove first writes the same fail-closed state, then marks the activation removed, clears rollback authority, and deletes the plugin's active, candidate, rollback, epoch, and trusted-decision grant state. Immutable revision bytes remain owner-only quarantine data for bounded revision-store garbage collection; their continued presence is not launch authority.

Activation records are written as `OMARCHY-ACTIVATION-V2`. The reader accepts the previous V1 record as enabled for forward compatibility, while V2 rejects contradictory `enabled=1` and `removed=1` state. Reinstall after removal must use a generation greater than the removed activation marker, so stale channels and handles cannot regain authority even though immutable content is retained.

`UpdateTransition::bind_active` rejects disabled and removed activations. `disable` and `remove` persist non-launchability before stopping the active worker, stop any attached candidate as well, clear runtime references, and report uncertain teardown as a health failure without making the durable activation launchable again.

## Adversarial matrix

| Operation or fault | Production seam exercised | Evidence and invariant |
| --- | --- | --- |
| Install | `LifecycleManager::stage`, revision store, grant store | `plugin-lifecycle`: pinned immutable content stages without replacing the current activation. |
| Enable | `LifecycleManager::enable` | `plugin-lifecycle`: required grants block enable; an exact trusted decision permits it. |
| Staged update | `UpdateTransition::stage` | `plugin-update-transition`: the old revision, worker, request, and surface stay live while the expanded candidate waits. |
| Approval | Candidate grant preview and exact trusted decision | `plugin-update-transition`: exact revision, policy fingerprint, mutation sequence, and actor are required before candidate launch. |
| Denial / incomplete approval | Grant store and transition readiness checks | `plugin-lifecycle` and `plugin-update-transition`: incomplete required grants and unreviewed candidate launch fail closed; candidate abort leaves old authority intact. |
| Activation fault before rename | Revision-store atomic record | `plugin-lifecycle` and `plugin-update-transition`: injected write/fsync faults preserve the old activation and grants. |
| Activation fault after rename | Lifecycle recovery | `plugin-revision-store` and `plugin-lifecycle`: recovery observes the committed exact identity and completes matching grant promotion, never a mixture. |
| Promotion fault after durable activation | D5 candidate promotion and D0 rollback | `plugin-update-transition`: failed old-worker teardown clears both runtime bindings, cancels tracked resources, and rolls durable state back with a fresh generation. |
| Rollback | Revision and grant stores | `plugin-lifecycle`: exact prior policy/grants return at a monotonically fresh generation; a missing target is denied. |
| Disable | Revision store, lifecycle, health supervisor, update transition | `plugin-revision-store`, `plugin-lifecycle`, and `plugin-update-transition`: a pre-commit fault leaves the prior enabled state; a committed disable survives host reconstruction and cannot bind a worker. |
| Revoke | Lifecycle, audited broker runtime, provider cancellation | `plugin-update-transition` and `plugin-broker-runtime`: persistence and audit admission precede cancellation; issued handles stale and new operations are denied. |
| Remove | Revision store, grant store, transition teardown | `plugin-lifecycle` and `plugin-update-transition`: the durable removed marker is non-launchable, rollback is cleared, all grant authority is erased, and restart does not resurrect it. |
| Failed health | D5 readiness and candidate teardown | `plugin-supervisor-health` and `plugin-update-transition`: a candidate that misses or fails readiness is stopped and cannot be promoted. |
| Worker crash | D5 pidfd-backed liveness, crash window, backoff, disable | `plugin-supervisor-health`: requests and exact surface keys are cleared, crash bursts back off and disable the exact revision, and stale generations remain rejected. |
| Broker restart | Durable grants plus broker runtime reconstruction | `plugin-broker-runtime`: a reconstructed broker consumes the persisted exact binding and grant epochs; revoked or forged authority remains denied and volatile handles are not restored. |
| Supervisor restart | Authoritative audit recovery | `plugin-supervisor-health`: unresolved worker-start audit records fail closed and prevent replacement admission until teardown is authoritative. |
| Shell restart | Host-owned lifecycle and worker state | `plugin-update-transition`: reconstructing the non-authoritative transition client cannot bind disabled or removed state; authority remains in the host lifecycle, broker, channel, and supervisor. |

## Fault and recovery ordering

```text
disable: durable enabled=false -> stop candidate/active -> clear session
remove:  durable enabled=false -> stop candidate/active -> durable removed=true -> erase grants
update:  stage/review/health -> durable activate -> promote candidate -> retire old
fault:   before durable boundary preserves old authority; after it recovers only the committed non-expanding state
```

An inability to confirm worker death poisons or quarantines the D5 supervisor slot. Disable/remove still return a health failure, but a host restart cannot use that uncertainty to reconstruct launch authority because the durable activation was made non-launchable first.

## Verification

The focused Debug and Release configurations build with `-Wall -Wextra -Wpedantic -Werror`. The F3 set is `plugin-revision-store`, `plugin-grant-store`, `plugin-lifecycle`, `plugin-broker-runtime`, `plugin-supervisor-health`, and `plugin-update-transition`. AddressSanitizer plus UndefinedBehaviorSanitizer runs the same lifecycle-critical set with leak detection disabled only where ptrace prevents LeakSanitizer from operating. Tests use temporary owner-only stores, deterministic fault points, fake process controls for forced teardown outcomes, and no active user resources.

The campaign does not claim secure erasure of immutable revision bytes, system package integration, or VM-only proof of kernel process-tree enforcement. Those remain revision GC, F5 packaging, and disposable-VM acceptance concerns respectively.
