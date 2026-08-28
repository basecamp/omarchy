# D1 Authenticated Channel Integration

## Outcome

D1 composes the C7 `Supervisor` and its B5 Bubblewrap launch with B3 endpoint negotiation and a narrow C4 dispatch boundary. No packet can reach broker policy/provider processing until the kernel-bound peer has completed independent control, broker, and render negotiations for one trusted launch generation.

The implementation lives in `native/plugin-runtime/channel-integration/`. It is deliberately not a provider runtime, grant engine, audit writer, revision activator, or health/restart policy. `BrokerDispatcher` is the seam through which the already-authenticated B3 packet enters C4/D4.

## Trust and state sequence

1. The trusted caller supplies a C7 `TrustedLaunchRequest`, a dispatcher owned by the trusted host, and a trusted `GenerationAuthority` tied to the serialized lifecycle activation domain.
2. C7 verifies the immutable revision/state directory descriptors, creates three private `SOCK_SEQPACKET` endpoints, starts Bubblewrap behind a barrier, obtains the authoritative outer child PID from Bubblewrap status, opens its pidfd, attaches the resource scope, and only then releases the worker.
3. D1 copies the C7 `LaunchIdentity` and requires exact plugin ID, revision digest, generation, outer UID/GID, positive outer PID, and live pidfd state before retaining the worker.
4. Each endpoint must send a valid B3 envelope-v1 HELLO on its inherited role FD. C7 validates `SCM_CREDENTIALS` against the outer launch identity and quarantines every delivered descriptor before D1 parses bytes. D1 independently negotiates control-v1, broker-v1, and render-v1 within a trusted wait bounded to 30 seconds before any deadline arithmetic.
5. D1 sends each endpoint's WELCOME or negotiation failure and marks the channel ready only after `RequiredEndpointReadiness` proves all three roles selected the same nonzero authoritative generation.
6. Broker dispatch is refused before aggregate readiness. After readiness, every incoming broker datagram again passes C7 credential, pidfd, descriptor, and size checks, then B3 envelope/endpoint parsing, exact negotiated broker version, exact launch generation, and the current trusted lifecycle-generation check before the C4 dispatcher can run.
7. A malformed HELLO/envelope, role substitution, unsupported or changed role version, stale generation, descendant credential, descriptor injection/truncation, peer exit, dispatch rejection, or exception from the trusted dispatcher is fatal. D1 contains every dispatcher exception at this boundary, closes endpoints, and delegates bounded pidfd/scope teardown to C7. A receive timeout alone is recoverable and has no dispatcher effect.

The channel's read-only `alive()` is pidfd-backed through C7 and is false after any channel failure or termination attempt. It is the narrow liveness seam for D5 health ownership; it does not expose the worker process or endpoint descriptors.

## Adversarial evidence

`channel_peer.cpp` promotes the relevant C11 malicious-peer behaviors into a negotiation-aware fixture. The fake-Bubblewrap suite covers dispatch before readiness, a request in place of HELLO, endpoint role substitution, unsupported negotiation version, post-negotiation role-version substitution, stale generation, descendant credentials, loss before and after readiness, a single descriptor, and a truncating 24-descriptor flood. Sixteen fresh sessions of both descriptor cases compare the broker's complete `/proc/self/fd` count before and after teardown.

The transport fixture additionally proves that the host can send the exact legal broker datagram maximum of 40 + 65,536 bytes, rejects one byte above that maximum, and returns promptly rather than blocking when independent broker and render queues are saturated by a worker that never reads. The shared C7 send primitive uses role-derived envelope-plus-payload caps and `MSG_DONTWAIT`; its existing at-most-one-descriptor rule is unchanged.

Every failed-authentication case uses a counting dispatcher and requires zero calls, which is the D1 proof that C4/D4 provider effects are unreachable before authentication. C4/D4 separately prove authorization and provider-side effect ordering after this boundary.

The real-Bubblewrap suite runs the valid and stale-generation cases through the production-shaped B5 argv/environment, PID/user namespaces, startup barrier, status-fd child identity, pidfd, three exact inherited endpoints, immutable revision bind, launch seccomp, and resource-scope contract. It requires one valid dispatch and zero dispatches for the stale peer.

## Commands and environment

```bash
cmake -S native/plugin-runtime/channel-integration -B /tmp/omarchy-d1-debug -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-d1-debug -j2
ctest --test-dir /tmp/omarchy-d1-debug --output-on-failure

cmake -S native/plugin-runtime/channel-integration -B /tmp/omarchy-d1-release -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/omarchy-d1-release -j2
ctest --test-dir /tmp/omarchy-d1-release --output-on-failure

cmake -S native/plugin-runtime/channel-integration -B /tmp/omarchy-d1-sanitize -DCMAKE_BUILD_TYPE=Debug -DPLUGIN_SECURITY_CHANNEL_SANITIZERS=ON
cmake --build /tmp/omarchy-d1-sanitize -j2
ASAN_OPTIONS=detect_leaks=0 ctest --test-dir /tmp/omarchy-d1-sanitize -R plugin-channel-integration-fake --output-on-failure
```

The credential and Bubblewrap tests must run outside Codex's managed outer sandbox on this development host: that outer sandbox returns `EPERM` from `SO_PASSCRED` before the D1 worker is launched. This is an environment constraint, not a security fallback. The real-Bubblewrap CTest has skip code 77 only when the Bubblewrap executable is absent; CI/VM acceptance on a supported Omarchy image must require a pass.

## Remaining integration boundary

D1 does not choose broker payload serialization and does not duplicate B3/C4 request/correlation state. This slice proves authenticated ingress plus the bounded C7 send transport; it intentionally defers the broker terminal-response pump and correlation ordering to the production D4 adapter. Production composition should instantiate a dispatcher backed by the D4 audited broker runtime. D4 remains responsible for grants, gestures, revocation, provider execution, terminal responses, and audit ordering. D5 remains responsible for health, restart budgets, and quarantine policy after D1 reports a fatal channel failure.

The standalone subproject is complete. Aggregate root registration is intentionally deferred to the coordinator's conflict-free integration commit because D3 and D5 concurrently own the shared root `native/plugin-runtime/CMakeLists.txt`.
