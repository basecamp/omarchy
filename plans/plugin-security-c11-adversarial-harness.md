# C11 malicious worker harness

## Outcome

C11 adds a reusable malicious worker and a bounded Linux harness under `native/plugin-runtime/tests/adversarial/`. It turns the B3/B6 attack descriptions into executable peer behavior that D1 and later proof campaigns can launch without teaching the production worker to expose test-only modes.

The worker contains no trusted validation logic. It independently constructs hostile wire bytes and can be selected by an explicit test argument. The harness owns the socket, enables kernel credentials, retains a pidfd, quarantines every received descriptor, classifies the attack through the production B3 contract, closes received descriptors through RAII, and reaps or kills the worker within a fixed deadline.

## Frozen minimized corpus

| Attack | Independent worker behavior | Expected trusted observation |
|--------|-----------------------------|------------------------------|
| `role-swap` | Sends a broker-role envelope on the control descriptor | Fatal `endpoint_role_mismatch` before role dispatch |
| `stale-generation` | Sends a well-formed control envelope with a different launch generation | Fatal `stale_generation` in selected endpoint state |
| `oversized` | Claims a 4,097-byte control payload | Fatal `payload_cap_exceeded` at the 4 KiB control cap |
| `descriptor-injection` | Attaches one `/dev/null` descriptor to an otherwise valid envelope | Kernel credentials and exact quarantined descriptor are visible; the consumer must reject the unexpected descriptor and RAII closes it |
| `descendant` | Forks and has the child send an otherwise valid envelope | `SCM_CREDENTIALS` PID differs from the retained worker PID, proving descendant substitution independently of envelope validity |
| `crash` | Raises `SIGABRT` | Retained pidfd becomes readable and the exact signal is observed |
| `hang` | Waits indefinitely | It remains live during the short observation window and is killed and reaped within the harness bound |

This node does not claim that the production supervisor is wired to every denial yet. D1 launches this same executable through C7 and connects it to the authenticated broker/channel integration. D5 consumes `crash` and `hang` for health and cleanup policy. F0 and F1 expand the minimized corpus only after a newly found bypass has been reduced to one deterministic case.

## Run

The credential tests require ordinary Linux `SO_PASSCRED` and pidfd behavior. Some outer development sandboxes deny that socket option; run the test in the repository's normal host/VM test environment in that case.

```bash
cmake -S native/plugin-runtime/tests/adversarial -B build/plugin-adversarial -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-adversarial
ctest --test-dir build/plugin-adversarial --output-on-failure
```
