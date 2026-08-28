# F1 Malformed Protocol and Resource-Exhaustion Proof

## Outcome

F1 assembles E0, E1, E2, E3, the C11 malicious peer, D5 health policy, and their real transitive contracts in one standalone CTest tree under `native/plugin-runtime/proof-exhaustion/`. The campaign does not replace owner tests with mocks: it runs the existing authenticated channel, render, QML, broker, provider, sandbox, health, descriptor-quarantine, and vertical-slice executables together, then repeats the deterministic high-pressure subset until failure.

The campaign found one production gap: D5 bounded concurrent requests but allowed an unlimited sequence of immediately completed requests. Commit `c773eeda` adds a fixed per-binding trusted-monotonic request-start window. Exceeding it or regressing the trusted clock tears down the worker before dispatch, records the failure, and enters the existing restart/backoff policy.

## Attack map

| Attack | Executable evidence |
|--------|---------------------|
| Truncated, malformed, wrong-role, stale, and oversized envelopes | F1 mutates 10,000 fixed-header packets and checks every truncation; B3/C11/D1 tests cover schema/order/credential teardown |
| Invalid, stale, replayed, truncated, and oversized frames | F1 rejects every truncated `FrameReady` and overflowing allocation; B4/D2/D3 tests cover shared-memory mutation, replay, pacing, and last-valid preservation |
| Descriptor and output floods | C11 repeatedly floods ancillary FDs and proves the open-FD set is invariant; B5 fixes bounded stdout/stderr pipes, burst/rate ceilings, file-size and FD rlimits |
| Excessive frame, request, input, and surface rates | D3/E2 enforce pre-copy FPS pacing and bounded regions; B3 fixes correlation capacity; D5 now tears down sequential request floods; E2/D5 cap surfaces and input state |
| Broker payload/result pressure | C4/C8 reject malformed demands, payloads above 60 KiB, crossed terminals, output-too-small results, and provider over-reporting; F1 independently exercises the oversized broker decoder path |
| Memory, scratch, CPU, process, and file exhaustion | B5/C7 tests require `MemoryMax`, private tmpfs size, `CPUQuota`, `TasksMax`, rlimits, no descendants, and bounded teardown; D5 tears down on authoritative memory/scratch/task excess |
| Crash loops and restart storms | C11 supplies crash/hang peers; D5 uses fixed revision-scoped crash history, exponential backoff, burst disable, stable reset, durable unresolved-worker recovery, and uncertain-teardown quarantine |

## Honest limits

The in-process F1 test verifies policy values and trusted accounting, not kernel enforcement by assertion. Actual namespaces, seccomp, cgroup properties, rlimits, descriptor quarantine, pidfds, crash/hang cleanup, and Bubblewrap denial remain the C11/B5/C7 executable tests included in the campaign. Real OOM kills, CPU throttling under sustained load, output-drain behavior, daemon restart, and systemd restart storms require the disposable Omarchy VM gate; they cannot be truthfully simulated in a unit process.

The request-start policy is a coarse fixed window using trusted whole seconds. It is intentionally deterministic and allocation-free. Production tuning must balance bursty interactive plugins against provider-side abuse; changing the default is policy tuning, while removing the per-binding bound is a security regression.

## Run

```bash
native/plugin-runtime/proof-exhaustion/run_campaign.sh /tmp/omarchy-plugin-f1-debug
F1_BUILD_TYPE=Release F1_STRESS_ITERATIONS=100 native/plugin-runtime/proof-exhaustion/run_campaign.sh /tmp/omarchy-plugin-f1-release
F1_SANITIZERS=ON ASAN_OPTIONS=detect_leaks=0 native/plugin-runtime/proof-exhaustion/run_campaign.sh /tmp/omarchy-plugin-f1-san
```

Set `F1_REAL_BWRAP=1` outside managed confinement on an Omarchy desktop/VM to add the real Bubblewrap paths. The C11 ambient-authority certificate still requires real `HOME`, session-bus, and Wayland prerequisites and must not be replaced by synthetic paths.

## Evidence

- Debug: the 14-test integrated campaign passed, followed by 25 uninterrupted repetitions of the deterministic corpus, supervisor rate/health policy, expressive surface, and brokered-action tests.
- Release: the same integrated campaign and 25-iteration stress subset passed. Fresh Release binaries also passed the real Bubblewrap channel, headless, and brokered-action paths outside managed confinement.
- ASan/UBSan with leak detection disabled: the 13-test instrumentable campaign passed, followed by 10 uninterrupted stress repetitions. The exact-environment sandbox-enforcement child is intentionally excluded from this configuration because it cannot inherit the LeakSanitizer override and its seccomp policy denies LeakSanitizer's ptrace probe; that test passes in Debug and Release. Address and undefined-behavior instrumentation remain active everywhere else.

The C11 ambient-authority certificate was not run in this tree because its required live session-bus and Wayland authority prerequisites are a separate desktop/VM gate. The campaign does run C11's deterministic malicious-peer harness in every configuration.
