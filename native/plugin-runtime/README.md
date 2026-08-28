# Omarchy plugin runtime skeleton

This directory is the native build root for the secured plugin runtime. B0 establishes packaging and process boundaries only; it does not implement a sandbox, grant policy, request broker, or render transport.

The host executable starts inert and holds no plugin authority. The worker denies every direct invocation except version reporting because no trusted launcher exists yet. The external `Omarchy.PluginHost` QML module reports `available: false` and the build version; it exposes no broker operations.

Contract work can land independently under `contracts/manifest`, `contracts/wire`, `contracts/surface`, `contracts/permissions`, and `contracts/sandbox`. The root discovers those directories only when their `CMakeLists.txt` exists.

Each contract also has an `OMARCHY_BUILD_<NAME>_CONTRACT` CMake option. It defaults on; turning one off is useful only for isolated development while that contract is incomplete.

Build and test locally:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
cmake --install build/plugin-runtime --prefix "$(mktemp -d)"
```

Packagers may set `OMARCHY_PLUGIN_QT_MIN_VERSION` when the supported Qt baseline is decided. This skeleton deliberately does not claim a production package or dependency policy.
