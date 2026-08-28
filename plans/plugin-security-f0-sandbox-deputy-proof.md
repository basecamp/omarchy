# F0 sandbox escape and confused-deputy proof

F0 composes the real C7/B5 sandbox harness, D1 authenticated channel, and E3/D4 action path into one proof tree at `native/plugin-runtime/proof-campaigns/sandbox-deputy`. The campaign found and fixed one trusted-host confused-deputy seam: D1 previously authenticated a worker and D4 independently bound its grants, but the selected `BrokerDispatcher` did not have to accept that same plugin, revision, and generation. A trusted routing error could therefore connect one plugin's worker to another plugin's grants and providers when their generation numbers happened to match.

`BrokerDispatcher::accepts` is now mandatory and fail-closed. D1 checks it against the kernel-bound C7 launch identity at open, after aggregate negotiation, before receive, and immediately before dispatch, terminates the worker on mismatch, removes the resource scope, and records zero dispatcher calls. E0's health wrapper and E3's audited runtime adapter both derive acceptance from their exact B2 activation binding; an authority-free downstream dispatcher cannot be attached directly.

The real Bubblewrap certificate now also creates a live host Unix agent socket and a sibling-plugin private-state marker before launch. The worker proves that both paths are absent, alongside the existing actual home, session-bus, and Wayland paths. It also proves the exact environment contains no agent variable, only descriptors 0–5 exist, the immutable revision cannot be written, AF_INET is denied, and descendants are denied. The E3 portion independently proves effect-free unknown operations, missing gestures, expanded scopes, unsupported URL actions, audit poisoning, and stale handles after revocation.

Run the strict campaign on an Omarchy desktop or VM that exposes a real session bus and Wayland socket:

```bash
cmake -S native/plugin-runtime/proof-campaigns/sandbox-deputy -B build/plugin-f0 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-f0 --target omarchy-plugin-f0-proof
ctest --test-dir build/plugin-f0 --output-on-failure --tests-regex 'plugin-(adversarial-harness|channel-integration-(fake|bwrap)|brokered-action(-bwrap)?)$'
```

Repeat with `-DCMAKE_BUILD_TYPE=Release`. For ASan/UBSan, configure with `-DPLUGIN_SECURITY_F0_SANITIZERS=ON`, build the `omarchy-plugin-f0-proof` target, and run the fake/host-side cases with leak detection disabled where the outer ptrace policy requires it. The real sandbox certificate intentionally retains its exact environment and remains the kernel-bound release-gate proof.
