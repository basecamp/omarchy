# E3 QML Brokered Action Vertical Slice

## Outcome

E3 proves that a QML-authored action can retain arbitrary QML expression while every system effect remains outside the plugin process and behind the authenticated, permissioned, audited broker path.

The standalone slice is `native/plugin-runtime/brokered-action/`. In the real-Bubblewrap case the worker loads `Main.qml` from the immutable `/plugin` revision bind. The QML object selects `storage.write` and supplies `from-qml`; the worker serializes that selection into the frozen broker-v1 request schema only after all three D1 endpoints negotiate the same generation.

## End-to-end binding

- C7/B5 launch the QML peer from an immutable revision with private control, broker, and render endpoints, outer PID/UID/GID credentials, pidfd identity, startup barrier, namespace, seccomp, and resource scope.
- D1 requires exact `org.example.secure`, revision digest `aa…aa`, generation 11, a matching live `GenerationAuthority`, and aggregate three-role readiness before broker dispatch.
- D4 constructs its permission authority and providers from the same activation binding. Its B3 state independently requires broker-v1, generation 11, a fresh nonzero correlation, and the registered operation schema.
- The allowed QML storage action requests the exact 4096/1024 quota. D4 durably appends an `operation_decided/allowed` audit record containing plugin, revision, generation, correlation, operation, capability, and decision before the provider receives key `k` and value `from-qml`.
- The denied QML notification action uses the requested `timer` scope but a denied grant. D4 appends the exact denial and never calls the notification provider.
- A handle issued from the allowed correlation is bound to plugin/revision/policy/generation/operation/scope/grant epoch. Revoking `storage.private` advances the epoch, and resolving the old handle returns `stale_grant`.
- If durable audit admission is made unavailable, D4 poisons before the provider call, the D1 dispatcher rejects the fatal runtime result, and C7 closes all endpoints and removes the resource scope. No provider effect occurs.

## Evidence

```bash
cmake -S native/plugin-runtime/brokered-action -B /tmp/omarchy-e3-debug -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-e3-debug -j2
ctest --test-dir /tmp/omarchy-e3-debug --output-on-failure

cmake -S native/plugin-runtime/brokered-action -B /tmp/omarchy-e3-release -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/omarchy-e3-release -j2
ctest --test-dir /tmp/omarchy-e3-release --output-on-failure

cmake -S native/plugin-runtime/brokered-action -B /tmp/omarchy-e3-sanitize -DCMAKE_BUILD_TYPE=Debug -DPLUGIN_SECURITY_BROKERED_ACTION_SANITIZERS=ON
cmake --build /tmp/omarchy-e3-sanitize --target omarchy-plugin-brokered-action-test -j2
ASAN_OPTIONS=detect_leaks=0 /tmp/omarchy-e3-sanitize/omarchy-plugin-brokered-action-test fake
```

The authenticated credential and real-Bubblewrap cases must run outside Codex managed confinement on this host because the outer sandbox denies `SO_PASSCRED`. CI/VM acceptance on a supported Omarchy image must require the real-Bubblewrap case to pass; code 77 is reserved for a missing Bubblewrap executable.

## Boundary

The QML fixture demonstrates request origination and the complete trusted action path, not a general QML-facing convenience API. C10 owns the stable `runtime.invoke` object and operation-specific serialization. D4 owns authorization, gestures, grants, providers, handles, revocation, terminal state, and audit ordering. D1 owns authenticated transport and fail-closed teardown. E3 adds no direct system API to QML.
