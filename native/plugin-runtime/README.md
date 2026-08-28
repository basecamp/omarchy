# Omarchy secure plugin runtime reference

This directory is the native build root for the secure schema-v2 plugin reference. The aggregate build includes the protocol and policy contracts, QML worker, Bubblewrap launcher, authenticated channels, broker, lifecycle and permission stores, render session, trusted surface bridge, representative vertical slices, and adversarial proofs.

The installed host executable deliberately remains inert. It supports version and launcher-prerequisite inspection, but it does not discover, activate, or execute plugins. The installed `Omarchy.PluginHost` QML module exports both `PluginHostInfo` and the authority-free `RemotePluginSurface` pixel/input endpoint. `PluginHostInfo.available` remains `false` until a product host composes discovery, lifecycle, supervisor, broker, and surface policy around that endpoint.

Schema v2 is therefore off for users even though its complete reference implementation is built and tested. Discovery and revision APIs default their feature state to disabled, the native permission inspector additionally requires trusted rollout state through `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`, and the existing schema-v1 commands remain explicitly unsafe compatibility behavior. The reference inspector binaries are not exposed through the end-user `omarchy` command router, and the packaged user unit remains disabled until a later product rollout.

Each contract has an `OMARCHY_BUILD_<NAME>_CONTRACT` CMake option that defaults on. Turning one off is for isolated contract development; dependent production targets are then omitted rather than treated as a secure partial runtime.

Build and test locally:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
cmake --install build/plugin-runtime --prefix "$(mktemp -d)"
```

Packagers may set `OMARCHY_PLUGIN_QT_MIN_VERSION` to enforce their supported Qt baseline. Building and installing the reference artifacts does not itself enable schema v2 or make the inert host a production activation service.
