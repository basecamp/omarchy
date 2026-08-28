# D5 limits, health, and recovery handoff

Status: implementation complete as a bounded supervisor component; daemon event-loop wiring remains with the later integration nodes.

## Boundary

`native/plugin-runtime/supervisor-health` consumes the trusted C7 launcher identity and termination API, the B4 `SurfaceKey`, and the C3 audit store. It does not parse plugin messages, accept plugin-selected policy, launch a process, or manufacture broker authority. The caller supplies an already validated `ActivationBinding` and host-monotonic timestamps.

The production `LauncherWorkerControl` owns the C7 worker object. Its liveness query is pidfd-backed, and its termination path disables all three receive channels before bounded pidfd, cgroup-tree, and monitor cleanup. D5 never signals a numeric PID or closes a plugin-supplied descriptor itself.

## Bounded state

The default policy permits at most 64 workers, 32 in-flight requests per worker and 256 globally, four surfaces per worker and 64 globally, 65,576 bytes per admitted request, 512 MiB memory, 64 MiB scratch, and 16 tasks. Policy construction rejects zero or representationally unsafe limits and cannot exceed the component's fixed arrays.

Request admission requires a ready worker, exact activation identity, a nonzero unique correlation, a bounded payload, and an overflow-safe deadline. Completion must name the exact live correlation. Surface admission stores the exact nonzero B4 surface ID and requires `SurfaceKey.generation == ActivationBinding.generation`; duplicate opens, wrong-generation opens/closes, and unknown closes cannot alter quota. Teardown clears every exact request and surface entry before authority can be replaced.

C7 and B5 remain the kernel enforcement owners for cgroup memory/tasks/CPU/IO ceilings, rlimits, namespace isolation, and bounded output pipes. D5 accepts trusted cgroup/scratch samples and tears down on excess. C7's pipe backpressure is the current output-memory bound; a rate-limited log drain requires a host event-loop sink and is intentionally not fabricated in this isolated component.

## Health and recovery

An adopted worker cannot serve requests or surfaces until an explicit readiness transition passes pidfd liveness and the startup deadline. Periodic `tick` checks pidfd liveness, startup timeout, and every fixed request deadline without sleeps. Any timeout, worker exit, or resource excess first removes the activation slot and all correlations/surfaces, then performs bounded C7 teardown.

Crashes are counted per exact plugin and revision within a bounded window. Restart delay doubles to a configured ceiling; the configured burst disables that exact revision. A different immutable revision has a separate budget. A sufficiently stable healthy period resets the in-memory budget.

The supervisor records started, health, crashed, stopped, and disabled transitions through the authoritative audit store with no operation, capability, correlation, path, payload, or secret field. On startup it recovers the durable audit and conservatively disables any exact revision whose latest retained supervisor transition is not a successful clean stop. This prevents a host crash from resurrecting an unresolved worker or resetting a crash loop. A clean stop removes that recovery tombstone.

If C7 cannot confirm teardown, the supervisor clears all live counters but retains the worker control as a quarantine tombstone, poisons itself, rejects and tears down every replacement, and retries termination during destruction. This is deliberately global fail-closed behavior because a failed pidfd/cgroup cleanup leaves worker lifetime ambiguous. Audit failure similarly poisons admission.

## Evidence

`plugin-supervisor-health` covers the readiness gate, exact identity, per-worker and global request/surface bounds, duplicate and stale surface keys, oversized requests, request timeout cleanup, stale correlations, pidfd-reported worker exit, exponential restart backoff, revision-scoped disable, resource excess, clean stop recovery, unresolved-worker recovery, redacted lifecycle audit, audit failure, and uncertain teardown quarantine. The latter proves counters reach zero while replacement admission remains impossible and the retained worker is not silently forgotten.

Run the isolated strict gate:

```bash
cmake -S native/plugin-runtime/supervisor-health -B build/plugin-runtime-d5 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_COMPILE_WARNING_AS_ERROR=ON
cmake --build build/plugin-runtime-d5
ctest --test-dir build/plugin-runtime-d5 --output-on-failure --tests-regex '^plugin-supervisor-health$'
```

Run the sanitizer gate with `-DPLUGIN_SECURITY_HEALTH_SANITIZERS=ON`. The transitive real Bubblewrap enforcement probe requires a host that permits its network namespace setup and is not evidence for this node; D5's focused test is synthetic, headless, deterministic, and bounded.

## Remaining gates

Daemon integration must call readiness only after the D1 handshake, call `tick` from its trusted monotonic event loop, feed authoritative cgroup and scratch usage, and route every accepted broker request and surface lifecycle through these counters. Disposable-VM testing still owns real OOM/cgroup exhaustion, output flood behavior with the eventual log sink, hostile descendant trees, host daemon crash and restart, session shutdown, and installed systemd restart behavior.
