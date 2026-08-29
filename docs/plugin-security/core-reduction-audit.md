# Secure plugin runtime reduction audit — batch A

This checkpoint is derived from `c2bf25cf` and contains only removal/defer cleanup. It does not introduce the policy extraction, native bridge additions, Quickshell integration, packaging, activation, or installed-system proof.

## Disposition

- Delete uninstalled experiments, proof campaigns, vertical slices, obsolete architecture/evidence notes, and redundant presentation/orchestration implementations that are not required by the retained build graph.
- Delete trusted external-provider administration, update/rollback orchestration, migration reporting, extended evidence tooling, and the standalone product host. Their later extension seams remain in subsequent batches; none are installed by this checkpoint.
- Delete all in-tree winner source, fixtures, capability definitions, screenshots, and references. Generic built-in definitions are not created in this batch and will be reviewed separately with the provider implementation that earns them.
- Retain the worker, bubblewrap/seccomp sandbox, authenticated channel, broker authorization, grant/revision/audit stores, provider registry, offscreen surface transport, and existing native QML module unchanged except for removing the deleted standalone host from version-reporting tests.

## Exact boundary

The 187 fully included paths and two partial paths are listed in `/tmp/omarchy-plugin-security-batch-a-paths.txt`. All other dirty paths are excluded and partitioned by `/tmp/omarchy-plugin-security-batch-{b,c,d,e}-paths.txt`.

The root CMake partial change removes only references to deleted batch-A targets. It retains `presentation`, `revision-store`, `grants`, `audit`, `broker-runtime`, providers, worker, trusted bridge, and channel integration. `native/plugin-runtime/tests/CMakeLists.txt` and `runtime_contract_test.cpp` drop only the deleted standalone-host version probe while retaining worker version, direct-launch denial, bridge import, and protocol tests.

## Exact budgets

| Measure | Baseline | Batch A | Delta |
|---|---:|---:|---:|
| Production C++ | 31,172 | 23,075 | -8,097 |
| Test/support C++ | 20,335 | 14,161 | -6,174 |
| Total native C++ | 51,507 | 37,236 | -14,271 |
| Production libraries/QML modules plus private worker | 31 | 20 | -11 |

Counts use the audit classifier: physical `*.cpp`, `*.h`, and `*.hpp` lines under `native/plugin-runtime`; test directories, fixtures, test/compatibility executables, fake/probe programs, `channel_peer.cpp`, and proof/vertical-slice code are support. The target count comes from CMake File API codemodel v2, counting production static/shared/module libraries plus `omarchy-plugin-qml-worker`, excluding test-only support/proof libraries.

These reproducible baseline classifications correct the existing working audit's 59-line production/support allocation mismatch; total baseline LOC is unchanged.

## Verification

Tested exact source: `/tmp/omarchy-plugin-security-batch-a-native.0SeHtU`.

- Configure: `cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-security-batch-a-native.0SeHtU-build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON` — pass.
- Full build: `cmake --build /tmp/omarchy-plugin-security-batch-a-native.0SeHtU-build -j2` — pass, 381/381 build steps.
- Environment-independent suite: `ctest --test-dir /tmp/omarchy-plugin-security-batch-a-native.0SeHtU-build --output-on-failure -E 'plugin-(sandbox-policy|sandbox-enforcement|sidecar-real-bwrap|worker-channel|qml-broker-api|channel-integration-fake|channel-integration-bwrap|adversarial-harness|malicious-peer|launcher-contract|launcher-malicious-peer|launcher-bwrap|launcher-systemd-scope)'` — 40/40 pass.
- Full CTest discovery/run: 53 tests; 40 ordinary passes, two expected launcher skips, and 11 restricted-environment failures. Every failure is attributable to denied network namespace or peer-credential setup, or the unavailable display; no source/build failure occurred. Those tests remain mandatory for later real-session validation.

## Proposed commit

`Remove superseded plugin security layers`

This checkpoint is not product-ready. It performs no live installation or activation and makes no claim that the standalone bridge is the product host.
