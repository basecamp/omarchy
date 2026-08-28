# E4 permission-expanding update and live-revocation handoff

Status: implementation complete as an independently testable vertical slice.

## Transition boundary

`native/plugin-runtime/update-transition` composes the existing D0 lifecycle stores, D1 authenticated channel, D4 audited broker runtime, and D5 health supervisor. It does not add a second source of identity, permission, launch, or audit authority.

The production `AuthenticatedChannelWorker` transfers ownership of an already negotiated and ready D1 channel to D5. Its identity is the C7 launch identity, liveness is the channel's pidfd-backed check, and termination uses D1's sticky three-channel teardown. Tests use the same `WorkerControl` seam with deterministic probes; they do not bypass lifecycle, grants, broker authorization, audit, or health state.

## Permission-expanding update

An update stages through D0 while the existing immutable revision, runtime, channel, requests, and surfaces remain live. The coordinator rejects a candidate unless its plugin, revision, policy fingerprint, generation, runtime grant fingerprint, and worker launch identity all agree with the staged stores.

Every added, expanded, incomparable, or requirement-changed capability must have a trusted-UI decision record bound to the exact candidate revision and policy fingerprint. The resulting grant record, scope, and decision must also agree; a historical decision without the corresponding current candidate grant cannot pass review.

The candidate may negotiate and pass D5 readiness while the old revision remains active, but candidate requests and surfaces are denied until promotion. Activation runs only after review and health both succeed. D0 atomically promotes the immutable revision and grants first, making D1's old generation stale immediately; D5 then terminates the old channel and clears every old correlation and exact `SurfaceKey` before marking the candidate active. An injected pre-rename activation failure leaves the old worker, request, surface, revision, and grants unchanged. A post-activation promotion failure invokes D0 rollback to the prior immutable revision with a fresh generation and does not continue with ambiguous process authority.

## Live revocation

Revocation first persists through D0 and rebinds the active grant fingerprint. D4 then appends the authoritative redacted `capability_revoked` event before mutating broker/provider state. It denies new operations at the incremented epoch, returns the exact in-flight correlations cancelled by the provider, and makes issued handles stale against the new epoch. A broker/audit mismatch tears down the active health slot instead of leaving the old in-memory grant live.

The coordinator immediately invokes D5 channel and process teardown when D4 returns `restart_worker`. The frozen B2 registry currently has no registered capability with `restart_worker`; its four capabilities use `deny_new` or `cancel_inflight`. E4 therefore proves the real emitted modes end to end and retains the production restart branch without inventing a new authority-bearing capability merely for coverage. Adding such a capability requires its own B2/C8 contract and provider review.

## Evidence

`plugin-update-transition` uses real manifest discovery, immutable revision/grant stores, lifecycle recovery, audited broker runtime, provider cancellation, and health accounting. It proves:

- an expanded storage scope plus an added fake-service scope remains staged while the old worker is live;
- unreviewed candidate workers are terminated and cannot receive request or surface authority;
- exact trusted decisions and candidate health are both mandatory;
- a revision-store fault preserves the old healthy revision and all tracked old resources;
- an old-worker teardown failure after durable candidate activation rolls lifecycle back to the prior immutable revision with a fresh generation, tears down the candidate, exposes no active runtime or binding, clears all tracked resources, and leaves the poisoned supervisor unable to admit either stale generation;
- successful activation terminates the old channel, clears its request and surface state, rejects its stale generation, and admits only the candidate generation;
- live fake-service revocation cancels the exact pending correlation and denies a new request;
- live storage revocation stales an exact issued handle; and
- the revocation audit sequence precedes the cancellation audit sequence.

Run the focused strict gate:

```bash
cmake -S native/plugin-runtime/update-transition -B build/plugin-runtime-e4 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_COMPILE_WARNING_AS_ERROR=ON
cmake --build build/plugin-runtime-e4 --target omarchy-plugin-update-transition-test omarchy-plugin-supervisor-health-test omarchy-plugin-broker-runtime-test
ctest --test-dir build/plugin-runtime-e4 --output-on-failure --tests-regex '^plugin-(update-transition|supervisor-health|broker-runtime)$'
```

Run the sanitizer gate with `-DPLUGIN_SECURITY_TRANSITION_SANITIZERS=ON`. LeakSanitizer may require disabling leak detection in the managed ptrace sandbox; AddressSanitizer and UndefinedBehaviorSanitizer remain active.

## Remaining system gates

The host event loop must send D4's returned cancellation correlations over D1 and wait for bounded terminal cleanup. Disposable-VM coverage still owns daemon death during the revision-first activation window, installed systemd recovery, real worker health failure and rollback relaunch, and a future reviewed capability whose contract legitimately requires `restart_worker`.
