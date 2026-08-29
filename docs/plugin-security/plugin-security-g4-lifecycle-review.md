# G3/G4 hostile lifecycle checkpoint

## Reviewed boundary

This checkpoint independently reviewed the E4 update transition and F3 durable lifecycle against crash windows, disable/remove/reinstall resurrection, candidate teardown, rollback generation monotonicity, corrupt stores, broker/supervisor/shell reconstruction, ambiguous worker teardown, and retained shared pointers.

## Findings fixed

1. A caller could retain a `shared_ptr<AuditedBrokerRuntime>` after successful promotion, rejected candidate admission, candidate abort, promotion failure, disable, or remove. Dropping the coordinator's pointer did not invalidate the retained broker, so it could still invoke host providers independently of the stopped or quarantined worker. `AuditedBrokerRuntime::shutdown` now permanently poisons dispatch, handles, completion, and direct provider mutation; admits cancellation records before cancelling in-flight provider work; and preserves audit-failure status across replay. Every transition rejection/retirement path shuts down the corresponding broker before releasing it.
2. `LifecycleManager::disable` called full revision/grant reconciliation before writing `enabled=false`. A corrupt grant store could therefore prevent a user-requested disable while leaving the durable activation launchable. Disable now depends only on the validated revision activation store. Recovery short-circuits disabled/removed activations without consulting corrupt grants, so restart remains non-launchable. Remove can still report failure when corrupt grants cannot be erased, but its durable removed marker is written first.
3. Reinstalling byte-identical content after disable/remove reused the old generation in staging. Activation then failed monotonically rather than resurrecting authority, but reinstall was unusable and the fresh-generation contract was not general. Staging now reuses a generation only for the same currently enabled activation; disabled or removed content receives the next checked generation.
4. Failed broker completion reported `output_too_small`, obscuring a poisoned shutdown. It now reports cancellation and writes no bytes.

## Regression evidence

- `plugin-lifecycle` corrupts the grant snapshot after enable, proves disable still commits, reconstructs the manager, and proves recovery does not consult or resurrect corrupt grant authority.
- `plugin-lifecycle` removes and reinstalls byte-identical content, proving the new binding is generation-fresh.
- `plugin-broker-runtime` creates asynchronous provider work, shuts down the runtime, verifies cancellation audit ordering, denies all later effects, rejects stale completion, and proves repeated shutdown preserves audit failure.
- `plugin-update-transition` retains old active, rejected/candidate, disabled, removed, and promotion-failed broker pointers and proves each is poisoned. Disable with an attached candidate tears down and poisons both generations.
- Existing revision-store, supervisor-health, and transition tests continue to cover atomic activation faults, monotonic rollback, pidfd-backed crash cleanup, ambiguous teardown quarantine, and restart rejection.

Debug, Release, and AddressSanitizer plus UndefinedBehaviorSanitizer run the six lifecycle-critical tests: `plugin-revision-store`, `plugin-grant-store`, `plugin-lifecycle`, `plugin-broker-runtime`, `plugin-supervisor-health`, and `plugin-update-transition`. Commit `c32121f3` moved the bounded permission collection storage off stack; a uniform sanitizer build now passes the E5/lifecycle dependency set with the ordinary 8 MiB stack. LeakSanitizer remains disabled only where ptrace or an exact sandbox environment prevents it from operating.

## Remaining boundary

Immutable removed revision bytes remain quarantined for bounded GC and are not authority. A failed cancellation audit poisons the broker before returning and worker teardown still proceeds; it cannot honestly claim that an already-running external effect was cancelled without an authoritative audit record. Kernel process-tree destruction and package-level erase remain disposable-VM and packaging evidence, not claims of this checkpoint.
