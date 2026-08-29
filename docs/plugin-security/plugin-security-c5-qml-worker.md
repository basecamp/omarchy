# C5 Unprivileged Arbitrary-QML Worker Handoff

## Outcome

The reference worker now loads and renders plugin-owned QML inside the B5 Bubblewrap boundary while all host authority remains on the other side of the three inherited `SOCK_SEQPACKET` endpoints. Plugins retain normal Qt Quick composition, animation, JavaScript, custom local components, drawing, and input handling. They do not create host windows, connect to a display server, open a broker or bridge socket, or receive an ambient system API.

This is intentionally not a declarative component library. The worker evaluates arbitrary plugin QML whose root is a `QQuickItem`, attaches that item to one worker-owned offscreen `QQuickWindow`, and publishes pixels into the B4 host-created two-slot frame region. System effects requested by QML remain future broker API calls; evaluating QML itself grants no filesystem, process, network, display-server, D-Bus, or device authority.

## Frozen worker boundary

`omarchy-plugin-qml-worker` rejects direct execution unless it is PID 1 and uid/gid 0 in the B5 user namespace, has exact worker environment values, and inherits three Unix sequence-packet sockets on FD 3, 4, and 5. This is defense in depth rather than launch authentication: the trusted host authenticates the worker by outer PID/pidfd and credentials, while the worker can only check its inherited peer baseline and translated credentials.

Each endpoint sends a B3 `HELLO`, accepts exactly one role-bound `WELCOME`, and participates in the shared launch-generation readiness gate. The channel receives into a pre-sized endpoint-cap buffer, rejects truncation before envelope parsing, requires one `SCM_CREDENTIALS` record, compares it with the inherited peer baseline, validates exact descriptor cardinality, and quarantines descriptors until the message has passed those checks. Rejected descriptors are closed by packet teardown. The worker has no path to select its plugin identity or generation.

After all roles are ready, the worker stacks the B5 steady-state seccomp allowlist before reading or instantiating plugin QML. `execve` and `execveat` are denied, `clone3` is denied, `clone` is limited to the documented thread flags, and Bubblewrap supplies the absent network/display/device mounts and cgroup limits. Control and broker role schemas are not yet integrated; unexpected post-negotiation traffic on those endpoints is fatal instead of being interpreted loosely.

## Loader and resource policy

The worker accepts only schema-v2 `runtime.qml` entries that are normalized relative `.qml` paths no longer than 512 bytes. The immutable `/plugin` tree is checked before loading with these reference limits:

- at most 4,096 filesystem entries and 64 MiB total content;
- at most 16 MiB per resource and 1 MiB per QML, JavaScript, or manifest file;
- regular files and directories only, with symlinks and special files rejected;
- URL imports cannot be absolute, remote, `file:`, or `qrc:` references;
- the QML engine import path contains only the plugin root, the installed Qt module root, and Qt's built-in QML resource root;
- intercepted filesystem module/resource loads are confined to the plugin tree or the `Qt`, `QtQml`, and `QtQuick` portions of the Qt module root;
- Qt image decoding is capped at 64 MiB per decoded image, matching the maximum 4,096 by 4,096 RGBA software surface. The focused corpus proves an ordinary PNG still decodes, a sub-1 MiB compressed 4,097-square PNG cannot allocate its 67 MiB output, and repeated truncated or unsupported inputs remain rejected. Qt's optional image-format plugins expand the parsers available inside the worker, but not the worker's filesystem, network, process, surface, cgroup, or restart authority. This does not claim parser correctness for every optional codec: a decoder fault still becomes an isolated worker exit, and D5's existing revision-bound crash budget supplies teardown, backoff, and disablement;
- component construction must finish synchronously, the root must be a `QQuickItem`, and the combined QObject/visual-item graph is capped at 4,096 objects both after construction and before each frame.

The source checks are safe from post-check substitution only because B5 mounts the selected content-addressed revision read-only. They are not a replacement for B1 identity validation or B5 mount immutability.

The initial profile is deliberately honest about compatibility. It uses Qt Quick's software adaptation and therefore does not support `ShaderEffect`, particles, arbitrary native QML plugins, Quickshell imports, top-level `Window`, multimedia/device modules, or GPU-only effects. Ordinary items, layouts available from the allowed Qt tree, local components, alpha, animations, JavaScript, and pointer/key/touch handling remain expressive. A later restricted GPU profile must be separately negotiated and threat-modeled rather than silently widening this profile.

## Rendering, input, and failure behavior

The host selects B4 software profile v1 and allocates one surface. The worker requires an exact-size, writable regular descriptor, maps it once, initializes the fixed shared layout, and never derives dimensions, offsets, or lengths from plugin data. `QQuickRenderControl` targets a premultiplied RGBA `QImage`; the software adaptation directly performs polish, sync, and render and must not call graphics-backend `initialize`, `beginFrame`, or `endFrame` methods. Every publication is a full frame and advances the selected slot by an even sequence before sending `FRAME_READY`.

The B4 surface state machine rejects duplicate allocation, stale generations, invalid suspend/resume/release transitions, input without an active focused surface, out-of-bounds input, and replayed sequences. Trusted input is translated into Qt pointer, button, wheel, key, and touch events on the offscreen window. A 16 ms timer drives and publishes the active scene so Qt animations advance even when the software render control does not emit a separate dirty signal; suspension and release stop publication.

Malformed envelopes, ambiguous one-way lifecycle failures, endpoint generation disagreement, invalid input/focus, and frame publication failure terminate the worker. Correlated profile or allocation failures return a typed render error where the B4 schema permits recovery. A worker hang or memory/CPU exhaustion cannot be handled in its event loop; C3/B5 host pidfd supervision, timeout, and cgroup kill semantics remain the authoritative crash/hang response. The trusted bridge keeps the last copied valid frame and never trusts the worker mapping in place.

## Evidence

`plugin-worker-runtime` performs a real headless Qt software render of animated arbitrary QML, passes the B4 frame through the trusted consumer, routes focused input, rejects replay, and exercises suspend/resume/release. Adversarial fixtures reject traversal, a plugin-created `Window`, a remote import, a symlink escape, a 5,000-item visual-object bomb, an oversized compressed image, and repeated malformed images. The seccomp fork proof requires `execve` to fail with `EPERM`.

`plugin-worker-channel` covers three-endpoint negotiation primitives, valid descriptor-free and one-descriptor render messages, descriptor injection cleanup, endpoint-role substitution, descendant credential substitution, and an above-cap sequence-packet datagram that must fail as truncated before parsing. The test needs a normal Linux Unix-socket environment; the managed development sandbox itself blocks `SO_PEERCRED` with `EPERM`, so that test is run outside that wrapper.

The executable additionally reports its version without initializing QML and returns exit status 78 when invoked directly without the exact B5 launch boundary.

## Downstream seams

- C6/D2 must connect the host-side render endpoint to the trusted bridge and prove continuous allocation, copy, upload, last-good-frame, teardown, and multi-surface behavior.
- D3 must connect surface placement and input routing while retaining the B4 host-owned geometry and monotonic gates.
- The broker-facing QML API must expose only typed B2/B3 operations and generation-bound handles. It must not reintroduce generic command, path, URL, D-Bus, or socket primitives.
- C3 must turn worker exit, channel EOF, missed readiness/health deadlines, and cgroup pressure into deterministic lifecycle outcomes.
- F2 must measure representative pets, overlays, drawers, and animated widgets against the software compatibility profile and identify which examples need a separately designed restricted GPU profile.
