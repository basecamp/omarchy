# External schema-v2 plugin fixtures

The external-fixture harness tests real plugin checkouts without copying competition entries into Omarchy or granting their QML ambient desktop authority. Each checkout remains independently versioned and is supplied as an absolute configure-time path:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime-winners -DBUILD_TESTING=ON \
  -DOMARCHY_PLUGIN_EXTERNAL_FIXTURES="/tmp/omagotchi-secure-port;/tmp/another-secure-port" \
  -DOMARCHY_PLUGIN_EXTERNAL_DEFINITIONS=/tmp/trusted-winner-definitions \
  -DOMARCHY_PLUGIN_EXTERNAL_ADAPTERS="private-storage:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1;desktop-notification:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:1"
cmake --build build/plugin-runtime-winners --target omarchy-plugin-external-fixture-test
ctest --test-dir build/plugin-runtime-winners -L external-fixture --output-on-failure
```

Every supplied checkout must have a schema-v2 `manifest.json`, a local `runtime.qml` entry point, and the named zero-argument `stepForTest()` hook. The hook is a deterministic compatibility seam for timers or random behavior; it is accepted only when its name ends in `ForTest`, and it is not reachable through the production worker protocol.

For each fixture the harness:

1. binds a runtime object exposing only `invoke(operation, arguments)` before QML loads;
2. loads capability definitions from an independently supplied trusted directory with the production no-symlink, ownership, mode, digest, and adapter-availability checks;
3. requires every manifest request to resolve the exact installed canonical name, definition generation, definition digest, and declared operation subset;
4. registers concrete fake adapters separately by class, implementation digest, and ABI;
5. proves a stale definition reference, plugin-only freeform name, adapter mismatch, undeclared operation, and ungranted operation all fail closed;
6. loads the real checkout through `WorkerRuntime` source-tree and QML restrictions;
7. invokes the named deterministic hook;
8. renders a 1280 × 720 software frame through the shared-memory transport; and
9. verifies that the trusted consumer receives non-transparent pixels.

Permission identifiers remain stable authority categories. Radio, AirPods, GitHub, and Omagotchi names belong in adapter registration and resource scope, never in the permission vocabulary. Definitions are not loaded from plugin checkouts. Registering an adapter does not grant it, granting a capability does not make an unregistered operation callable, and changing either definition or adapter code invalidates its independently pinned digest.

This is a functional compatibility proof, not an activation or sandbox-escape proof. It deliberately does not install a plugin, mutate grants, call real providers, or enable the dormant production host. Radio, AirPods, GitHub, and later winner ports join the same suite by adding their checkout paths at configure time; no Omarchy source change is required.
