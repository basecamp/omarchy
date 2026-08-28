# E1 Arbitrary-QML Embedded Bar Slice

## Result

E1 composes the existing C5, D1, D2, D3, D4, and B5 seams into a standalone vertical proof for the C10 Pomodoro. The exact schema-v2 fixture is loaded by `WorkerRuntime`, receives one trusted `runtime` context object before QML creation, renders complete arbitrary-QML pixels through the B4 memfd transport, and appears only inside D3's host-assigned 252×48 `bar-embedded` envelope. The worker never receives a Quickshell item, compositor handle, window-placement object, filesystem path API, raw descriptor API, or permission authority.

The new C5 seam is deliberately narrow: `bind_runtime_api(QObject&)` binds the fixed context name `runtime` exactly once and only before QML load. It rejects parents, dynamic or declared properties, and every declared method except the exact public `QVariant invoke(QString,QVariantMap)` shape. The object remains host/worker-runtime code, not plugin code. Its invokable surface is still subject to the D1 authenticated dispatcher contract and D4 authorization/audit path; binding a QObject does not make the QML engine a policy authority. The worker import boundary now explicitly includes the base `QtQml` module required by standard attached types such as `Component`, while continuing to reject modules outside `Qt`, `QtQml`, and `QtQuick`, remote imports, and relative imports that escape the immutable plugin root.

## What the proof exercises

- The current Pomodoro manifest selects its named `timer` surface. D3 verifies the B2 activation plugin, revision, policy fingerprint, and generation before allocating the bar.
- The current Pomodoro QML performs `storage_read` during creation through the fixed `runtime.invoke` SDK shape. The E1 adapter serializes the registered B3 `storage_read` operation and quota demand, enters through the D1 `BrokerDispatcher` seam, and reaches D4. The dispatcher binds exactly to the runtime plugin, revision, and generation and rejects a crossed plugin identity. The storage provider observes the durable redacted allow audit before the read.
- D2 negotiates the software render profile and real host-created memfd with C5. The first frame and an input-driven repaint cross the real worker publication, private trusted copy, and C6 image path.
- A bar click and touch sequence use D3's transient worker-focus bracket. C5 translates them with runtime-owned synthetic mouse and touchscreen devices, and the worker receives focus only for the bounded pointer/touch lifecycle while the host surface remains persistently unfocused and keyboard-ineligible.
- A named storage write is allowed and audited. Optional notification and audio requests are explicitly denied and invoke no backend. An undeclared `open_uri` name never becomes a broker packet. Audit export contains neither the storage key nor value.
- Teardown sends the exact generation-bound `surface_release`; the real worker drops its writable mapping, render/input/focus state, and the host clears its private pixels. The E1 test also consumes the frozen B5 plan and requires isolated user/PID/network namespaces, no shared network, no Wayland environment, immutable revision and private-state FD mounts, and only worker protocol FDs 3/4/5. The standalone tree includes the D5 supervisor-health suite, and the transitive D1 and B5 CTests remain the executable kernel-bound credential and ambient filesystem/network/process denial evidence; E1 does not replace them with an in-process claim.

## Honest boundary

This is the first complete embedded-bar data-path proof, not installed daemon wiring. The D1 production channel still owns kernel peer identity and launch, while this deterministic E1 executable calls the same identity-bound `BrokerDispatcher` seam in-process so render, input, broker authorization, and audit failures remain attributable. The D1 real-Bubblewrap and B5 enforcement tests run in the same standalone CTest tree and must pass on an Omarchy host that permits user/network namespaces. D5 remains the owner of live worker/surface/request quotas, health ticks, crash budgets, and restart teardown; its real contract and focused tests are included rather than manufacturing another lifecycle authority inside E1.

The version-1 software profile still excludes ShaderEffect, particles, GPU rendering, partial damage, IME, clipboard, drag and drop, accessibility, global shortcuts, and plugin-owned popups. Full arbitrary QML within supported QtQuick/software behavior remains intact.

## Evidence commands

```bash
cmake -S native/plugin-runtime/vertical-slices/embedded-bar -B /tmp/omarchy-e1-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-e1-debug -j2
ctest --test-dir /tmp/omarchy-e1-debug --output-on-failure

cmake -S native/plugin-runtime/vertical-slices/embedded-bar -B /tmp/omarchy-e1-release -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-e1-release -j2
ctest --test-dir /tmp/omarchy-e1-release --output-on-failure -R 'plugin-embedded-bar-slice|plugin-surface-host|plugin-render-session'

cmake -S native/plugin-runtime/vertical-slices/embedded-bar -B /tmp/omarchy-e1-san -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON -DPLUGIN_SECURITY_E1_SANITIZERS=ON
cmake --build /tmp/omarchy-e1-san --target omarchy-plugin-embedded-bar-test -j2
ASAN_OPTIONS=detect_leaks=0 ctest --test-dir /tmp/omarchy-e1-san --output-on-failure -R '^plugin-embedded-bar-slice$'
```

Credential and real-Bubblewrap tests require execution outside the managed Codex sandbox on this development host because the outer sandbox denies `SO_PASSCRED` and network-namespace setup. Packaging, installed systemd/Quickshell wiring, compositor placement, visual acceptance, and clean-VM proof remain F2/F5 work.
