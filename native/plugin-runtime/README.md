# Omarchy secure plugin runtime reference

This directory is the native build root for the secure schema-v2 plugin reference. The aggregate build includes the protocol and policy contracts, QML worker, Bubblewrap launcher, authenticated channels, broker, lifecycle and permission stores, render session, trusted surface bridge, representative vertical slices, and adversarial proofs.

The installed host remains dormant unless an operator invokes its explicit `--preview-plugin PLUGIN_ROOT TREE_SHA256 GRANT_STORE PRIVATE_STATE AUDIT_STORE` command with `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`. Preview accepts only immutable schema-v2 content with matching active reviewed grants, launches the arbitrary-QML entry point in the Bubblewrap worker, and displays its first declared surface through a host-owned `RemotePluginSurface`. Starting the systemd unit, installing files, or setting the feature flag alone does not discover or activate anything. The preview broker has no authority, so all plugin actions are denied; connecting reviewed generic grants to registered provider adapters is a separate product integration step.

Schema v2 is therefore off for ordinary users even though its reference implementation and explicit preview are built and tested. Discovery and revision APIs default their feature state to disabled, the native permission inspector and preview additionally require trusted rollout state through `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1`, and the existing schema-v1 commands remain explicitly unsafe compatibility behavior. The reference inspector and preview are not exposed through the end-user `omarchy` command router, and the packaged user unit remains disabled until a later product rollout.

An additional `--preview-plugin-live-lab` command takes the preview arguments followed by `WORKER_PATH WORKER_SHA256 BUNDLE_SHA256` and also requires `OMARCHY_PLUGIN_LIVE_LAB_ENABLED=I_ACCEPT_LAB_RISK`. It is intended only for a disposable validation account or VM with a separately created grant, state, and audit root. The complete installed runtime is rooted at `/opt/omarchy-plugin-security-lab/<BUNDLE_SHA256>`, where the bundle identity covers the mode, digest, and relative path of every installed artifact. The worker must be root-owned at `<LAB_ROOT>/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker`; every path component must be root-owned, non-symlinked, and not group- or world-writable, and the worker is independently rehashed against `WORKER_SHA256` before launch. This keeps a lab build side-by-side with Omarchy 4.x without replacing `/usr/share/omarchy`, its schema-v1 plugins, or the production worker path. Unlike the ordinary preview, it runs an audited broker for compiled private-storage, desktop-notification, and packaged-audio operations. It executes the fixed Omarchy notification helper and `pw-play` without a shell; notification text is passed only as argv data and audio assets resolve only below the verified plugin revision's `sounds/` directory. The ordinary preview continues to instantiate `DenyAllBroker`, and neither command is automatic installation or activation.

Each contract has an `OMARCHY_BUILD_<NAME>_CONTRACT` CMake option that defaults on. Turning one off is for isolated contract development; dependent production targets are then omitted rather than treated as a secure partial runtime.

Build and test locally:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
cmake --install build/plugin-runtime --prefix "$(mktemp -d)"
```

Packagers may set `OMARCHY_PLUGIN_QT_MIN_VERSION` to enforce their supported Qt baseline. Building and installing the reference artifacts does not itself enable schema v2 or make the inert host a production activation service.
