# A3 supplement: External host-module import spike

## Question

Can Omarchy ship a native `QQuickItem` as an external QML module and load it into a generic Qt QML engine and the existing Quickshell process without modifying or forking Quickshell?

## Probe shape

The scaffold under `experiments/plugin-security/host-module/` builds a dynamically loaded QML extension plugin with the URI `Omarchy.PluginHost`. It exports `HostProbeItem`, a deliberately inert subclass of `QQuickItem` that uses only public Qt APIs and exposes a constant marker property.

The plugin is installed into an isolated prefix with the standard URI-derived layout:

```text
<prefix>/lib/qt6/qml/Omarchy/PluginHost/
  libomarchy-plugin-host.so
  qmldir
  omarchy-plugin-host.qmltypes
```

The generic smoke-test executable links Qt but does not link the plugin. It adds only `<prefix>/lib/qt6/qml` to its import path, evaluates `import Omarchy.PluginHost`, creates `HostProbeItem`, and verifies the native property. This distinguishes a real dynamic import from static type registration leaking through the test executable.

## Run

Build, install into the isolated build prefix, and test the generic engine with:

```bash
experiments/plugin-security/host-module/run-test.sh
```

The Quickshell test is opt-in so routine builds do not start another shell process:

```bash
experiments/plugin-security/host-module/run-test.sh experiments/plugin-security/host-module/build --quickshell
```

The Quickshell invocation uses the offscreen Qt platform, a short temporary XDG runtime directory, and separate state, cache, data, and config directories beneath the ignored build directory. Its one-pixel configuration has a unique path identity, imports the module, and prints its marker. The harness terminates that isolated process after three seconds and treats only the expected marker as success. It neither connects to the running Omarchy shell nor uses its IPC/runtime paths.

## Result

On Qt 6.11.2, CTest and the installed-prefix generic host both loaded `Omarchy.PluginHost`, constructed the native `QQuickItem`, and read `probeMarker=omarchy-plugin-host-loaded`. Inspection of the installed generic host confirms that it has no dynamic dependency on `libomarchy-plugin-host.so`; the type became available through QML's dynamic plugin loader.

An isolated Quickshell 0.3.0 invocation also loaded the installed-prefix module and printed:

```text
host-module-quickshell-smoke: omarchy-plugin-host-loaded
```

This local Quickshell binary was built against Qt 6.11.0, while the installed libraries and the probe module use Qt 6.11.2. Quickshell warns that this mismatch may crash because Quickshell itself uses private Qt APIs. The module loaded successfully in this run, but that does not make the mismatch supported or suitable as release evidence. The disposable-VM acceptance test must rebuild or install Quickshell against exactly the active Qt release before repeating the probe.

The isolated Quickshell run also reported that it could not start its own IPC server in the temporary runtime directory. IPC is not used by this import test, and module construction completed despite that warning. The clean-VM repeat should require both an ABI-matched Quickshell and normal isolated IPC initialization so the final installed-path proof does not inherit this environment-specific caveat.

The live import trace independently showed `/usr/lib/qt6/qml` in Quickshell's default `QQmlEngine` import list. The production package can therefore install the module under `/usr/lib/qt6/qml/Omarchy/PluginHost` without setting a user-controlled `QML_IMPORT_PATH`; the isolated probe uses that variable only because its installation root is deliberately outside `/usr`.

## Interpretation

An external module is the preferred trusted bridge shape if both probes pass. It lets Omarchy keep frame validation and the `QQuickItem` scene-graph adapter in a narrow separately tested library while leaving the upstream Quickshell executable unchanged.

This does not make the module a separate security boundary. It runs inside the trusted shell process and can crash or compromise that process. Production requirements therefore include narrow public-API code, hostile-input tests before data reaches the item, exact package ownership, and installed-path validation in the disposable VM.

The test also does not prove the eventual frame uploader. `HostProbeItem` intentionally has no scene-graph node, shared-memory mapping, protocol parser, or input forwarding. `G0` freezes their authority and transport seams; `B4`, `C6`, and `D2` own the live writable-slot contract, fake bridge consumer, and integrated worker/daemon/bridge loop.

## Fixed memfd frame proof

`HostFrameItem` extends the dynamic module with the smallest bounded frame-consumer seam. The test host creates an 8 × 4 memfd with three bytes of leading padding to exercise an unaligned host-owned offset, fixes its length, then forks a minimal producer. The producer maps the descriptor read-write, writes one translucent premultiplied RGBA frame, closes its descriptor, and exits. After reaping the producer, the host adds grow, shrink, write, and seal seals before passing its remaining descriptor to the module.

The module keeps the configured 8 × 4 geometry and byte offset as trusted state. Worker-declared metadata cannot select either value. For each import it:

- rejects dimensions and payload length that do not exactly match the host allocation;
- duplicates the caller-owned descriptor with `F_DUPFD_CLOEXEC` before inspecting it so validation and mapping retain one owned file description;
- verifies the descriptor is a regular memory file, is large enough for the host-owned offset and length, and has the required fixed/immutable seals;
- calculates the aligned mapping range from host-owned values with a 64 MiB hard limit;
- maps the descriptor with `PROT_READ` only;
- constructs a premultiplied RGBA `QImage` view with the host-owned width, height, and stride;
- immediately copies that view into a host-owned `QImage`; and
- unmaps the worker-visible storage before publishing the trusted copy.

The valid import produced a 128-byte trusted image with exact translucent RGBA bytes and a stable SHA-256 digest. The host then closed its final memfd descriptor. Imports containing a wrong width, wrong length, unsealed memfd, truncated sealed memfd, or pipe descriptor returned false, left an explanatory error, and did not replace the last valid image or digest. Negative and over-limit offsets and a 4,097-pixel dimension were rejected without changing the configured generation. A later valid reconfiguration incremented the surface generation and cleared the old image, preventing a stale frame from being presented under new geometry. The same test passes from both the build tree through CTest and the isolated installed prefix.

The raw descriptor method is named `importFrameForTest` intentionally. It is test scaffolding, not the production QML API. The production bridge should receive an owned descriptor from the supervisor behind an opaque authenticated surface handle; neither plugin QML nor ordinary trusted presentation QML should pass integer descriptors.

This is deliberately a one-frame immutability proof, not the production streaming protocol. A live two-slot producer cannot apply `F_SEAL_WRITE` while it continues rendering. That design needs a bounded sequence or ownership handoff around each slot and must copy into trusted memory only when the sequence remains stable across validation and copy. Such a sequence detects torn or superseded writes; it does not authenticate the producer, plugin identity, surface identity, authorization, or payload. Those identities remain properties of the supervisor-created channel and host allocation.
