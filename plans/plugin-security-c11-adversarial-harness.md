# C11 malicious worker harness

## Outcome

C11 adds a reusable malicious worker and a bounded Linux harness under `native/plugin-runtime/tests/adversarial/`. It turns the B3/B6 attack descriptions into executable peer behavior that D1 and later proof campaigns can launch without teaching the production worker to expose test-only modes.

The worker contains no trusted validation logic. It independently constructs hostile wire bytes and can be selected by an explicit test argument. The harness owns the socket, enables kernel credentials, retains a pidfd, quarantines every received descriptor in aligned ancillary storage before interpreting truncation or policy, classifies the attack through the production B3 contract and a fake authenticated channel gate, closes received descriptors through move-only RAII, and reaps or kills the worker within a fixed nonblocking deadline.

## Frozen minimized corpus

| Attack | Independent worker behavior | Expected trusted observation |
|--------|-----------------------------|------------------------------|
| `role-swap` | Sends a broker-role envelope on the control descriptor | Fatal `endpoint_role_mismatch` before role dispatch |
| `stale-generation` | Sends a well-formed control envelope with a different launch generation | Fatal `stale_generation` in selected endpoint state |
| `oversized` | Claims a 4,097-byte control payload | Fatal `payload_cap_exceeded` at the 4 KiB control cap |
| `descriptor-injection` | Attaches one `/dev/null` descriptor to an otherwise valid envelope | Kernel credentials and exact quarantined descriptor are visible; the consumer must reject the unexpected descriptor and RAII closes it |
| `descriptor-flood` | Attaches eight descriptors to a four-descriptor quarantine | `MSG_CTRUNC` is denied only after every delivered descriptor is quarantined; sixteen attempts leave the trusted open-FD set unchanged |
| `descendant` | Forks and has the child send an otherwise valid envelope | `SCM_CREDENTIALS` PID differs from the retained worker PID, proving descendant substitution independently of envelope validity |
| `crash` | Raises `SIGABRT` | Retained pidfd becomes readable and the exact signal is observed |
| `hang` | Waits indefinitely | It remains live during the short observation window and is killed and reaped within the harness bound |
| standalone sandbox | Runs the same worker through the C7 supervisor and real B5 Bubblewrap plan | Complete FD set and environment multiset, a read-only existing revision file, absence of the pre-proved actual host home plus actual session-bus and Wayland sockets, denied network socket and descendant, pre-release scope attachment, and bounded teardown are all certified |

The fake channel verifier explicitly suppresses dispatch for unexpected descriptors, truncated ancillary data, and a PID/UID/GID tuple that differs from the launch binding. The standalone sandbox path uses C7 and B5 but does not connect the production broker, so D1 still owns end-to-end authenticated broker/channel teardown. D5 consumes `crash` and `hang` for health and cleanup policy. F0 and F1 expand the minimized corpus only after a newly found bypass has been reduced to one deterministic case.

## Run

The credential tests require ordinary Linux `SO_PASSCRED` and pidfd behavior. Some outer development sandboxes deny that socket option; run the test in the repository's normal host/VM test environment in that case. The complete ambient-authority certificate additionally requires `HOME`, `XDG_RUNTIME_DIR`, and `WAYLAND_DISPLAY`, with a real directory, session-bus socket, and Wayland socket visible to the host before launch. A headless runner cannot substitute synthetic `/tmp` paths and claim this proof; use the Omarchy desktop/VM gate.

The sanitizer configuration instruments the malicious worker, harness, wire library, sandbox policy and host-side enforcement test, and launcher. The B5 payload probe itself remains uninstrumented because its exact environment cannot admit `ASAN_OPTIONS` and its seccomp policy intentionally denies LeakSanitizer's helper process. Debug teardown is also stress-run repeatedly so a launch-monitor race cannot hide behind the single CTest invocation.

```bash
cmake -S native/plugin-runtime/tests/adversarial -B build/plugin-adversarial -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-adversarial
ctest --test-dir build/plugin-adversarial --output-on-failure
```
