# B6 deterministic security test fixtures

Status: implementation complete; Linux adversarial and sanitizer/fuzz-smoke evidence must be rerun when a consumed contract changes.

## Boundary

B6 supplies deterministic test infrastructure for the plugin runtime. It does not implement a second manifest, envelope, render, permission, or sandbox validator. Tests call the public B1 manifest, B3 wire, and B4 render contracts when those targets are present. The optional test CMake hook lets those owners remain independently buildable while exposing their reviewed contracts to this shared harness.

The literal envelope corpus under `native/plugin-runtime/tests/fixtures/wire/v1` is an independent copy of the frozen B3 wire examples. Every case records the trusted endpoint role and exact expected result next to literal bytes, so a protocol edit cannot silently regenerate its own expected output. B1 retains the authoritative manifest fixtures. B4 retains authoritative render schema vectors until separately reviewed copies are intentionally promoted into this corpus.

## Deterministic primitives

`Omarchy::PluginTestSupport` provides:

- a manual monotonic clock with explicit overflow failure;
- monotonic deterministic IDs with no zero identity;
- a stable, bounded truncation and bit-flip mutation campaign;
- literal hexadecimal fixture decoding and encoding;
- RAII descriptor ownership, exact `/proc/self/fd` observation, and collision-safe relocation to worker FD 3, 4, and 5 followed by `close_range`;
- `SOCK_SEQPACKET`, `SO_PASSCRED`, aligned ancillary parsing, automatic quarantine/closure of received `SCM_RIGHTS`, and truncation or malformed-control reporting;
- real `pidfd_open`, strict poll-state classification, bounded signal/reap cleanup, and no sleep-based lifetime guesses;
- a disposable synthetic revision, private state, and fake home rooted at a unique `/tmp/omarchy-plugin-fixture.*` directory.

The support test proves deterministic ordering, exact wire round trips, typed failure expectations, one-byte-over role caps, descriptor cleanup, synthetic resource cleanup, and consumption of the public manifest lifecycle and render codec. It never reads a real home directory, session bus, display socket, agent socket, device, or plugin state.

## Malicious-peer evidence

The Linux adversarial test creates three real `SOCK_SEQPACKET` endpoints and a forked worker. The worker collision-safely enters with exactly FD 0 through 5, where FD 3, 4, and 5 are control, broker, and render. A passed `/dev/null` descriptor is received into quarantine and is proven absent after the packet scope. A descendant sends a valid broker envelope but is rejected by the test decision because its kernel `SCM_CREDENTIALS` PID is not the pidfd-bound worker PID. The bound worker sends a valid render envelope while its pidfd is live.

A separate worker queues a valid, correct-credential control packet and exits. The packet remains syntactically valid, but the readable pidfd proves its authority lifetime has ended, so the harness treats it as unacceptable. A closed pidfd is classified as unusable, never alive. These checks demonstrate the identity and lifetime inputs a production receiver must require; they do not claim that the test harness itself is a production broker.

The test has finite poll/reap deadlines, sends acknowledgements rather than sleeping, uses only synthetic sockets and `/dev/null`, and closes or reaps every owned kernel resource.

## Sanitizer and fuzz-smoke gates

Run the ordinary focused suite from a configured runtime build:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime-b6 -G Ninja -DBUILD_TESTING=ON -DOMARCHY_BUILD_PERMISSIONS_CONTRACT=OFF -DOMARCHY_BUILD_SANDBOX_CONTRACT=OFF
cmake --build build/plugin-runtime-b6 --target omarchy-plugin-support-test omarchy-plugin-malicious-peer-test
ctest --test-dir build/plugin-runtime-b6 --output-on-failure --tests-regex '^plugin-(test-support|malicious-peer)$'
```

Run address/undefined behavior instrumentation with `native/plugin-runtime/tests/support/scripts/run-sanitizers.sh`. Run the Clang/libFuzzer bounded smoke campaign with `native/plugin-runtime/tests/support/scripts/run-fuzz-smoke.sh`. The latter executes 512 deterministic cases per available public contract, applies explicit input-size ceilings, and wraps each process in a 30-second outer timeout. It seeds manifest fuzzing from the B1-owned valid fixture and envelope fuzzing from the independent literal B3 corpus; the render seed is deliberately arbitrary and does not become a competing schema vector.

## Environment gates

The pure helper, literal corpus, mutation, lifecycle, and codec checks are headless and portable across supported Linux build hosts. Kernel-credential, pidfd, `close_range`, and adversarial FD identity tests require an unsandboxed Linux test runner that permits the corresponding syscalls and socket options. A managed development sandbox may deny `SO_PASSCRED`; such a denial is an environment gate, not passing evidence.

VM-only acceptance remains necessary for the production sandbox's real mount namespace, cgroup placement and enforcement, seccomp filter, device denial, network denial, session bus/display/agent isolation, tree teardown under hostile descendants, compositor integration, installed systemd unit, and distribution packaging. B6 deliberately does not probe the active user's resources to approximate those claims.

## Exit criteria

B6 is satisfied when the literal corpus and support tests pass against the reviewed B1/B3/B4 public targets, the malicious-peer suite passes on an unsandboxed Linux runner, the sanitizer suite reports no finding, the bounded fuzz smoke reports no crash, and no fixture owns real user resources or relies on wall-clock sleeps. A protocol or schema change invalidates this evidence until the owner updates its contract and B6 is rerun; B6 must not regenerate expected bytes as part of that rerun.
