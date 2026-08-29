# External schema-v2 plugin fixtures

The external-fixture harness tests real plugin checkouts without copying competition entries into Omarchy or granting their QML ambient desktop authority. Each checkout remains independently versioned and is supplied as an absolute configure-time path:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime-winners -DBUILD_TESTING=ON -DOMARCHY_PLUGIN_EXTERNAL_FIXTURES="/tmp/omagotchi-secure-port;/tmp/another-secure-port"
cmake --build build/plugin-runtime-winners --target omarchy-plugin-external-fixture-test
ctest --test-dir build/plugin-runtime-winners -L external-fixture --output-on-failure
```

Every supplied checkout must have a schema-v2 `manifest.json`, a local `runtime.qml` entry point, and the named zero-argument `stepForTest()` hook. The hook is a deterministic compatibility seam for timers or random behavior; it is accepted only when its name ends in `ForTest`, and it is not reachable through the production worker protocol.

For each fixture the harness:

1. binds a runtime object exposing only `invoke(operation, arguments)` before QML loads;
2. derives generic authority grants from required and optional manifest requests;
3. registers concrete fake adapter operations separately from those grants;
4. proves a registered adapter without its generic grant returns `permission-denied`, while an unregistered product-specific operation returns `unknown-operation`;
5. loads the real checkout through `WorkerRuntime` source-tree and QML restrictions;
6. invokes the named deterministic hook;
7. renders a 1280 × 720 software frame through the shared-memory transport; and
8. verifies that the trusted consumer receives non-transparent pixels.

Permission identifiers remain stable authority categories such as `storage.private` and `notifications.send`. Radio, AirPods, GitHub, and Omagotchi names belong in adapter registration and operation schemas, never in the permission vocabulary. Registering an adapter does not grant it, and granting a capability does not make an unregistered operation callable.

This is a functional compatibility proof, not an activation or sandbox-escape proof. It deliberately does not install a plugin, mutate grants, call real providers, or enable the dormant production host. Radio, AirPods, GitHub, and later winner ports join the same suite by adding their checkout paths at configure time; no Omarchy source change is required.
