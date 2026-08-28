# G0 Plugin Security Seam Synthesis

## Checkpoint status

`G0` is **closed**. The trust map, native build shape, Bubblewrap namespace identity, 40-byte three-channel envelope, offscreen renderer, external Quickshell module, bounded memfd consumer, and test ownership freeze the shared seams without requiring the downstream implementation to exist. The focused proofs and the integrated Wave 0 harness pass, and independent hostile review found no remaining seam-gate blocker.

`G0` is a seam-and-mock gate, not an integrated-system gate. Fresh package/ISO proof belongs to `F5`; the real worker/shared-memory/bridge loop belongs to `D2` after isolated `C5` and `C6`; systemd recovery, full lifecycle, visual fidelity, and hostile-system testing remain owned by their downstream nodes. Wave 1 may build against the frozen contracts and fake peers; items marked **pending contract** or **deferred** remain downstream work rather than G0 evidence.

## Inputs reviewed

| Node | Design artifact | Executable evidence | G0 assessment |
|------|-----------------|---------------------|---------------|
| `A0` | [`plugin-security-a0-trust-map.md`](plugin-security-a0-trust-map.md) | Current implementation paths in `bin/`, `shell/`, `default/hypr/`, and `config/` | Complete. Every trusted component, authority, and cross-boundary channel has one logical owner. |
| `A1` | [`plugin-security-a1-native-build.md`](plugin-security-a1-native-build.md) | `experiments/plugin-security/native-build/` | Local build, embedded QML module, offscreen execution, CTest shape, CMake install rule, staged archive, and ELF shape are sufficient for the G0 build seam. Clean installed-environment proof is `F5`. |
| `A2` | [`plugin-security-a2-channel.md`](plugin-security-a2-channel.md), [`plugin-security-a2-bwrap-identity.md`](plugin-security-a2-bwrap-identity.md), and [`plugin-security-a2-envelope.md`](plugin-security-a2-envelope.md) | `experiments/plugin-security/channel/`, including `bwrap-identity/` and `envelope/` | Complete. The inherited three-channel Bubblewrap launch, fail-closed outer PID/pidfd binding, descendant and role-substitution denial, descriptor allowlist, bounded teardown, 40-byte envelope, independent role negotiation, direction-scoped correlation, and ancillary quarantine pass focused and hostile review. |
| `A3 renderer` | [`plugin-security-a3-render-transport.md`](plugin-security-a3-render-transport.md) | `experiments/plugin-security/render-transport/` | Animated QML renders offscreen through the Qt software scene graph without Wayland/X11. Software rendering is explicitly an incomplete compatibility profile. Full transport integration is downstream. |
| `A3 host module` | [`plugin-security-a3-host-module.md`](plugin-security-a3-host-module.md) | `experiments/plugin-security/host-module/` | A public-API external `Omarchy.PluginHost` QML plugin loads dynamically in a generic engine and isolated Quickshell without a fork. Its fixed-size memfd consumer validates and copies a sealed frame, rejects malformed metadata, preserves the last valid frame, and survives producer exit. |
| `A4` | [`plugin-security-a4-test-survey.md`](plugin-security-a4-test-survey.md) | Existing `test/cli`, `test/shell`, `test/acceptance`, systemd-unit patterns, and sibling-repository availability | Complete. Eight verification layers, exact entry points, node ownership, package/VM boundaries, and current environment gaps are recorded. |

## Compatible decisions ready to freeze

### Native build and artifact ownership

1. Production native code uses **C++20, CMake, and Ninja**.
2. The initial linked Qt set is **Qt Core, Gui, Qml, and Quick**. The worker uses native `QQuickRenderControl`; it is not implementable as QML-only shell code.
3. Host, worker, shared wire implementation, worker SDK, and trusted bridge ship atomically in the existing `omarchy` package. The external `omarchy-pkgs` repository owns final PKGBUILD dependency and build integration.
4. The initial physical artifact shape is:

   ```text
   /usr/bin/omarchy-plugin-host
     trusted supervisor and broker-core executable

   /usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker
     private sandbox worker, not on the ordinary user PATH

   private worker resources
     worker-side QML SDK compiled into the worker executable

   dynamically imported Qt QML module
     narrow trusted remote-view bridge loaded by Quickshell
   ```

5. `omarchy-plugin-host`, the lifecycle manager, supervisor, broker, grant authority, and bridge remain logically separate authorities as defined by `A0`, even where the first implementation places supervisor and broker-core modules in the same trusted executable. Code boundaries and tests must preserve those ownership rules.
6. The worker cannot infer plugin identity, revision, grants, or authority from its executable name, command line, environment, plugin manifest, or direct invocation. A direct worker launch without supervisor-created descriptors fails closed.

Freeze `/usr/lib/qt6/qml/Omarchy/PluginHost` as the package-owned module layout. The external-module spike installed the URI-derived tree there under an isolated prefix, dynamically loaded it without linking the host executable to the plugin, and found `/usr/lib/qt6/qml` in Quickshell's default import list. The worker remains private libexec; its exact `/usr/lib/omarchy/...` subdirectory can be finalized by `B0` without changing the boundary. ABI-matched packaged Quickshell import, normal Quickshell IPC startup, package dependencies, and installed permissions remain `F5` evidence.

### Supervisor lifetime

Freeze the version-1 deployment model as a **graphical-session-scoped systemd user service**, not a child of `omarchy-shell` or `bin/omarchy-launch-shell`.

1. `omarchy-plugin-host.service` owns the lifetime of the trusted host daemon and every plugin worker cgroup beneath it.
2. The unit is wanted by and part of `graphical-session.target`, following the repository's existing user-session pattern in `default/systemd/user/omarchy-crash-watch.service`, `omarchy-sleep-lock.service`, and `omarchy-fcitx5.service`.
3. The service daemon starts independently of Quickshell, survives a deliberate shell restart, and terminates all worker generations when the graphical session stops.
4. Systemd owns daemon restart limits and the top-level service cgroup. The plugin supervisor owns per-plugin/per-generation child scopes or cgroups, worker restart budgets, pidfds, and teardown within that service lifetime.
5. `omarchy-shell` is a reconnecting presentation client. Shell death removes bridge-owned surfaces but does not transfer worker identity or broker authority into the replacement shell. The daemon either pauses visual workers or preserves their last non-visible state according to the lifecycle contract, then reattaches only through a fresh trusted bridge session.
6. The daemon constructs worker environments from its own allowlist. It does not pass through the systemd user manager's session environment merely because the unit has it.

The repository-supported unit relationship to carry into `B0` is:

```ini
[Unit]
After=graphical-session.target
PartOf=graphical-session.target
ConditionEnvironment=OMARCHY_PATH
ConditionEnvironment=WAYLAND_DISPLAY

[Service]
Type=simple
ExecStart=/usr/bin/omarchy-plugin-host
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

This follows `omarchy-crash-watch.service` and `omarchy-fcitx5.service`: it cannot start as a stale headless service under an SSH-created lingering user manager, remains independent of Quickshell, and stops with the graphical session. The core daemon does not `Require=` the session bus merely because some future provider may use it. The packaged unit must be added to `install/user/first-run/enable-user-units.sh` so first login enables and starts it through the established path.

This is a G0 architectural decision supported by the existing systemd user-unit pattern and the requirement that plugin and shell failures have separate lifetimes. Socket activation, restart timing/burst limits, child-scope mechanism, shell-absence behavior, and migration wiring remain `B0`/`B5` implementation contracts and require their downstream tests.

### Worker identity and channel bootstrap

1. Each worker channel is an unnamed `AF_UNIX` `SOCK_SEQPACKET | SOCK_CLOEXEC` socket pair created by the trusted launcher before sandbox entry.
2. Exactly three worker endpoints are inherited at fixed descriptors in protocol version 1: control at **FD 3**, broker RPC at **FD 4**, and render/input at **FD 5**. All unrelated descriptors are closed before worker execution.
3. Every trusted endpoint enables `SO_PASSCRED` and requires valid kernel `SCM_CREDENTIALS` on every worker packet. Payload identity and role fields are untrusted data and never select authorization context or endpoint role.
4. The production launch binding contains canonical plugin id, activated revision digest, worker role, worker generation, UID, and a **pidfd**. Numeric PID may be recorded for diagnostics but is not the lifecycle identity.
5. The endpoints are neither filesystem-named nor reconnectable. EOF or process replacement destroys the affected generation binding. A restart receives three new socket pairs, a new pidfd, generation, and handle namespace.
6. Receiving `SCM_RIGHTS` is denied unless the selected message type explicitly permits a bounded descriptor count and defines the descriptor's type, size, access mode, ownership, and lifetime.

The historical `A2` spike proves that a worker payload claiming `forged.admin` remains authorized only as the launch-bound `trusted.clock`; its single FD 3 topology is not the frozen production shape. The Bubblewrap supplement proves the production-shaped FD 3/4/5 launch tuple, binds all three endpoints to Bubblewrap's reported outer worker PID and retained pidfd, rejects role substitution and otherwise-valid traffic from an unbound fork descendant on every role, and closes all unrelated descriptors. Its occupied-reserved-FD mode also proves that fixed endpoint assignment does not depend on lucky source descriptor numbers.

### Physical channel topology

Freeze the version-1 topology as **three role-specific worker channels terminating at `omarchy-plugin-host`**, plus a separate trusted daemon-to-Quickshell bridge session:

```text
sandbox worker
  +-- FD 3 control ------ private SOCK_SEQPACKET --+
  +-- FD 4 broker RPC --- private SOCK_SEQPACKET --+--> omarchy-plugin-host daemon
  +-- FD 5 render/input - private SOCK_SEQPACKET --+              |
                                                                    | trusted local bridge session
                                                                    v
                                                     native module inside Quickshell
```

The supervisor creates all three pairs as one launch tuple bound to the same canonical plugin id, revision, worker role, generation, UID, and pidfd. The daemon is the sole root of worker identity, grants, surface allocation, and worker lifecycle. Direct worker-to-Quickshell endpoints are forbidden because they would create a second worker-identity bootstrap, bind worker lifetime to a restartable presentation process, and expose the boundary to Quickshell's general IPC/runtime directory. The bridge never accepts a worker-created connection or worker-selected surface handle.

The endpoint roles and descriptor policies are:

| Worker FD | Role | QoS and failure policy | Descriptor policy |
|----------:|------|------------------------|-------------------|
| 3 | Control | Reserved queue for negotiation, readiness, health, graceful shutdown, and fatal protocol state. A render or broker flood cannot delay it; pidfd termination remains out of band. | `SCM_RIGHTS` always forbidden. |
| 4 | Broker RPC | Independent request/response/event/cancellation bounds and backpressure. Broker failure can deny operations without consuming render queue capacity. | Forbidden by default; use opaque handles. A future descriptor-bearing operation requires an explicit versioned schema. |
| 5 | Render/input | Frames may be dropped or coalesced under pressure without delaying lifecycle or broker results. Surface faults can close this role independently before supervisor policy decides whether to terminate the worker. | Only explicitly typed host-created frame-buffer descriptors, with bounded count, size, access mode, surface, generation, and lifetime. Worker-originated descriptors are denied in the initial profile. |

Physical separation provides kernel-queue QoS and keeps render ancillary-data parsing away from control. A single multiplexed socket cannot fully prevent head-of-line blocking or apply per-family descriptor policy before packets share the same receive queue. The cost is cross-channel ordering: every message carries the common worker generation plus role-specific sequence/state, and stale surface, grant, revoke, or shutdown messages fail closed.

The exact daemon-to-bridge socket address or socket-activation scheme, same-user peer authentication, reconnect handshake, descriptor-transfer protocol, and behavior while the bridge is absent belong to `B3`/`B4` contracts and `C6`/`D2` proof. G0 freezes that it is separate, trusted, daemon-authenticated, and never worker-facing; it does not require that integration to exist.

### Common control envelope

Protocol version 1 freezes the outer packet envelope specified and executably proven by `A2`:

| Offset | Size | Field | Version 1 rule |
|-------:|-----:|-------|----------------|
| 0 | 4 | Magic | ASCII `OMPL`, network byte order (`0x4f4d504c`) |
| 4 | 2 | Envelope version | Exactly 1 |
| 6 | 2 | Header size | Exactly 40 |
| 8 | 2 | Endpoint role | 1 control, 2 broker RPC, 3 render/input; must equal the trusted FD binding |
| 10 | 2 | Message type | Common handshake/error type or a type from the selected role protocol |
| 12 | 2 | Role protocol version | Zero during `HELLO`; selected independently by `WELCOME` on each endpoint |
| 14 | 2 | Flags | Must be zero in envelope version 1 |
| 16 | 4 | Payload length | Exact bytes following the header and no more than the bound endpoint cap |
| 20 | 4 | Reserved | Must be zero in envelope version 1 |
| 24 | 8 | Launch generation | Zero in worker `HELLO`; supervisor-assigned and exact after selection |
| 32 | 8 | Correlation id | Zero for uncorrelated handshake/events; nonzero for request families |
| 40 | N | Payload | Message-specific untrusted bytes |

Additional frozen rules:

- One `SOCK_SEQPACKET` packet is exactly one envelope; messages are never stream-reassembled.
- Endpoint caps are role-specific: control is **4,096 bytes** (4,136-byte packet), broker RPC is **65,536 bytes** (65,576-byte packet), and render/input is **16,384 bytes** (16,424-byte packet). Bulk pixels and unbounded provider bodies never travel inline in this envelope.
- Receivers use fixed buffers plus `MSG_TRUNC`, reject truncation and length disagreement, and parse no payload until magic, version, type, flags, size, credentials, and descriptor policy pass.
- The first worker packet on each of FD 3, FD 4, and FD 5 is `HELLO`; each trusted endpoint independently replies with `WELCOME` selecting its role protocol version and the same authoritative launch generation, or sends a bounded negotiation failure and closes.
- Unknown message types, nonzero reserved flags, midstream version changes, missing credentials, unexpected credentials, excess descriptors, and malformed envelopes fail closed.

Request ids, cancellation, error taxonomy, event semantics, concurrency bounds, timeouts, and message-specific serialization are not part of the outer envelope freeze. `B3` owns them.

### Initial rendering boundary

1. The first reference path uses **Qt Quick software rendering** in the sandboxed worker. It receives no Wayland, X11, D-Bus, or GPU render-node connection.
2. Before `QGuiApplication` construction, the supervisor supplies an explicit environment selecting the offscreen platform, a neutral platform theme, software scene graph, and `QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0`. The worker also calls `QQuickWindow::setGraphicsApi(QSGRendererInterface::Software)` before creating its window/render control. It does not inherit user Qt platform, theme, graphics, or import-path variables.
3. The worker creates a dedicated `QQmlEngine`, loads plugin QML as an arbitrary `QQuickItem`, parents it to a `QQuickWindow` driven by `QQuickRenderControl`, and renders premultiplied RGBA pixels without creating a native display window.
4. The Qt software path uses `polishItems()`, `sync()`, and `render()` against `QQuickRenderTarget::fromPaintDevice`. It must not use the graphics-API `initialize()`, `beginFrame()`, or `endFrame()` lifecycle.
5. The first transport is host-created, fixed-capacity shared memory with **two frame slots**. Dimensions, capacity, format, surface role, and generation originate in trusted host allocation. The worker cannot resize the object or nominate a path, pointer, texture id, or arbitrary buffer.
6. Version 1's initial pixel format is fixed premultiplied 8-bit RGBA. Other formats are rejected until explicitly versioned.
7. Frame readiness is signaled over authenticated render/input FD 5; the trusted host validates surface id, worker generation, slot, logical and pixel dimensions, DPR, stride, payload length, sequence, and damage metadata against its allocation before upload.
8. The trusted bridge is a small native `QQuickItem` loaded by the existing Quickshell process. It consumes only supervisor-issued surface handles, displays the last valid frame, clips pixels and input to assigned geometry, and forwards only bounded host-derived presentation and input events. It never loads plugin QML, manifests, grants, or arbitrary paths.
9. File-backed PNG frames and a QML `Image` with polling/cache invalidation are diagnostic-only and forbidden as the production transport.

The shared-memory design is ready to freeze at this level, but its race-free publication algorithm is **pending contract**. A read-only mapping in the host is not enough because the worker still holds a writable mapping to the same pages. `B4` must define slot state, sequence ownership, memory ordering, copy/upload behavior, post-copy validation, and recovery from a worker modifying a committed slot. Security-sensitive code must treat frame metadata and all shared pages as `U2` throughout; calling a worker-written frame header “trusted” does not make it trusted.

This software renderer is an **incomplete reference compatibility profile**, not fulfillment of full arbitrary-QML fidelity. Qt's software adaptation does not render `ShaderEffect` or particle effects and differs for transformed text. The initial profile can claim ordinary Qt Quick items, layouts, text within the tested limitations, raster/image content, alpha, timers, and ordinary animations only as each receives a fixture. Plugins requiring shaders, particles, or other unproven scene-graph features remain unsupported in secure mode or require the later restricted-GPU profile. The UI, manifest tooling, migration inventory, discussion, and PR must disclose this limitation rather than silently dropping effects.

Disabling partial updates makes every published buffer self-contained, which is required when alternating slots. Re-enabling damage rendering is a later optimization and requires a preservation test proving that unchanged pixels survive when a slot does not contain the immediately preceding frame.

### Trust ownership

The `A0` authority assignments are compatible with the Wave 0 executable spikes and are ready to freeze:

| Authority | Owner |
|-----------|-------|
| Source validation, immutable revision insertion, activation, rollback, and removal transaction | Lifecycle manager |
| User-selected capability scopes and revocation state | Grant authority/store |
| Worker identity, activated revision binding, sandbox/cgroup, descriptors, generation, health, and process-tree teardown | Supervisor |
| Packet validation, current-grant check, rate/concurrency enforcement, handles, and typed dispatch | Broker core |
| Domain operation and secret use after broker authorization | Narrow broker provider |
| Wayland surface role, location, geometry, z-order, focus, input, frame limits, trusted identity treatment, and lock exclusion | Trusted surface host/bridge |
| Arbitrary QML evaluation and pixels | Untrusted worker |
| Append-only redacted security/lifecycle evidence | Audit writer |
| Explicit permission, unsafe-mode, and state-retention decisions | User through trusted Omarchy UI/CLI |

Manifests request; SDK shims request; marketplace metadata informs; plugin pixels display untrusted content. None grants or enforces authority.

## Completed bounded memfd seam

The external module now includes the narrow hostile-input seam required by G0:

- the trusted side creates a fixed-size memfd and seals it against growth and shrinkage;
- a separate producer writes one premultiplied RGBA frame and exits;
- the completed test frame becomes immutable before trusted import;
- the native item validates offset, length, dimensions, format, and configured surface capacity before copying;
- the copy lands in host-owned memory rather than leaving a live image alias over worker-writable pages; and
- bad dimensions, bad length, invalid descriptors, and producer exit preserve the last valid digest/frame and do not crash the generic host.

The focused rerun passed `external-host-module-import` and `fixed-memfd-frame-import` through CTest, then passed both from the isolated installed prefix. The frame smoke reaped the producer, copied 128 bytes, reported digest `3abeabcf914764361471215f1fe95d9b1439f287a8d191766949801d08ab64c0`, denied malformed dimensions and length, and preserved that digest. Code review confirms trusted geometry/offset, a 4,096-pixel dimension cap, 64 MiB mapping cap, `fstat`/regular-file/size checks, required grow/shrink/write seals, page-aligned read-only mapping, immediate `QImage::copy()`, and unmapping before publication.

This closes only the FD/mapping/validation seam. It does not claim a scene-graph node, live double-buffer publication, input, daemon-to-bridge IPC, or real worker. A live producer cannot apply `F_SEAL_WRITE`; `B4` must define stable sequence/ownership validation around each writable slot. `C6` owns the fake-producer bridge component, and `D2` owns the complete worker/transport/bridge loop and race-resistant live shared-memory protocol.

## Completed Bubblewrap identity seam

The focused [`A2` Bubblewrap supplement](plugin-security-a2-bwrap-identity.md) and `experiments/plugin-security/channel/bwrap-identity/` now prove:

- the supervisor creates the FD 3/4/5 endpoint tuple and records the Bubblewrap-reported outer worker PID plus a retained pidfd before releasing its startup barrier;
- Bubblewrap enters separate user, PID, mount, IPC, UTS, network, and optionally cgroup namespaces while the worker receives only standard descriptors and its three assigned endpoints;
- FD 0/1/2 normalization happens before channel allocation, two-phase descriptor relocation survives deliberately occupied fixed destinations, each non-destination original is closed, and `close_range` removes every non-allowlisted descriptor;
- kernel credentials observed by the trusted parent match the recorded outer worker identity across the namespace boundary;
- each endpoint accepts only its assigned role, rejects role substitution, and rejects otherwise-valid traffic from an unbound fork descendant whose kernel PID differs; and
- every receive polls the retained worker pidfd beside the role socket and rechecks it after receipt, treating `POLLNVAL` and every unexpected nonzero event as fatal; a closed-pidfd injection denies an already queued correct-credential packet, and an inherited-endpoint holder is killed when PID 1 exits and leaves no acceptable post-lifetime packet; and
- all waits are bounded, the barrier is SIGPIPE-safe, a direct-child guard covers monitor-pidfd acquisition with only bounded nonblocking reap attempts, and failure cleanup signals through retained pidfds and reaps the Bubblewrap monitor.

The launch pins `/usr/bin/bwrap`, constructs a minimal pre-Bubblewrap environment, fixes the inner `PATH`, `PWD`, and hostname, and uses `--disable-userns` plus the supported `--assert-userns-disabled`. Its bounded Bubblewrap JSON-lines parser ignores unknown records/members while rejecting duplicate authoritative keys, requiring typed range-checked `child-pid` and `exit-code`, and preserving both if one record contains both. The probe uses the already-installed json-c parser as an explicit spike-only dependency; production must either reuse the native host's robust parser or justify adding json-c rather than silently inheriting it for two status fields.

## Evidence still required before gate closure

### Three-channel envelope conformance

The 40-byte envelope is design-frozen in [`plugin-security-a2-envelope.md`](plugin-security-a2-envelope.md), and its fixture under `experiments/plugin-security/channel/envelope/` passes the golden header, independent role negotiation, stale generation, correlation/cancellation races, typed error, fatal malformed packet, role-specific cap, asymmetric credential model, exact descriptor cardinality, and descriptor-quarantine cases. The older 16-byte single-channel fixture remains historical forged-identity and truncation evidence only; it is not a production wire fixture.

This is not the complete sandbox policy or systemd lifecycle proof. `B5` freezes the mount/environment/resource policy, `C7` implements it, `D1` integrates supervisor/sandbox/broker, and `F0` performs installed escape/confused-deputy attacks.

The systemd service lifetime and channel topology are design-frozen. Session startup/shutdown, shell and daemon restart, cgroup cleanup, daemon-to-bridge authentication, bridge reconnect, descriptor transfer, QoS under flood, and stale cross-channel ordering are downstream implementation evidence. Replacing the systemd-scoped daemon with a shell child, collapsing the three worker endpoints, or adding a direct worker-to-Quickshell endpoint reopens G0 because each changes an authority or QoS seam.

## Deferred and downstream evidence

### Supported Qt minimum

`A1` declares Qt 6.5 as its probe minimum while `A3` declares Qt 6.8. Both ran locally on Qt 6.11.2. Production must select the oldest version actually present in every supported Omarchy repository/CI/VM and verify that `QQuickRenderTarget::fromPaintDevice`, the chosen software lifecycle, QML module APIs, and bridge scene-graph APIs compile and behave there. Until then, freeze Qt 6 Core/Gui/Qml/Quick as dependencies, not a numeric minimum.

### Test and VM ownership

`A4` freezes test ownership as follows:

| Layer | Authoritative location and entry point | Boundary |
|------|----------------------------------------|----------|
| CLI routing and metadata | `test/cli`; `./test/cli` | Command routing, help, aliases, metadata, argument errors, and non-executing `--help` |
| Headless shell/command integration | `test/shell.d/*-test.sh`; `./test/shell` | Fake-home lifecycle, manifest/discovery, static QML invariants, pure models, and local negative cases |
| Existing non-graphical aggregate | `./test/all` | CLI plus shell only; never native, graphical, package, fuzz, benchmark, or visual proof |
| Native correctness/security | `native/plugin-runtime`; CMake build in `build/plugin-runtime`; CTest | Labels `unit`, `protocol`, `adversarial`, `property`, and `integration` |
| Installed graphical acceptance | `test/acceptance.d/*-test.sh`; `test/acceptance`, driven from sibling `omarchy-iso` | Real packaged Quickshell, Hyprland, surfaces, input, service manager, cgroups, and session sockets |
| Packaging | Sibling `omarchy-pkgs`; `./bin/build --mirror edge --package omarchy` | Package recipe, dependencies, PKGBUILD `check()`, archive paths, ELF inspection |
| Fuzz/property corpora | `test/plugin-security/fuzz/<target>/`; opt-in `PLUGIN_SECURITY_BUILD_FUZZERS=ON` | Persistent fuzzing is release evidence; minimized regressions become deterministic CTest cases |
| Benchmarks | Native benchmark target; machine-readable results in `build/plugin-runtime/results/` | Informative local baselines; pinned-VM release measurements are distinct from correctness |
| Visual verification | Local screenshot/video commands plus acceptance screenshots/logs in `$OMARCHY_ACCEPTANCE_DIR` | Required in addition to automation for every visual change |

The production PKGBUILD runs the complete bounded CTest suite with `BUILD_TESTING=ON`; persistent fuzz campaigns and performance thresholds do not run in `check()`. Headless Qt tests use the reviewed offscreen/software environment. Real Quickshell imports, layer shell, Hyprland input, multi-output/DPR, installed systemd units, and session-socket denial belong in disposable-VM acceptance.

Shared protocol, manifest, render, sandbox, and malicious-peer fixtures live under `test/plugin-security/`, with fuzzer seeds and minimized regressions under `test/plugin-security/fuzz/<target>/`. Benchmark records under `build/plugin-runtime/results/` use a versioned machine-readable object containing fixture/protocol version, Git revision, Qt version, renderer/backend, resolution, DPR, monitor count, CPU, GPU when applicable, sample count, and distribution statistics rather than only an average. Required benchmark families are frame production, frame copy/presentation, input round trip, broker latency, startup, steady-state memory, crash recovery, rate-limit behavior, and 1/10/60-second frame pacing. `B4` sets informative initial budgets after measuring the integrated transport; local developer timings do not become merge thresholds.

Current environment gaps are exact and non-negotiable:

- This workspace has no sibling `omarchy-iso` checkout, so acceptance and fresh-ISO commands cannot run here.
- The available sibling `omarchy-pkgs` checkout has no `pkgbuilds/*/omarchy/` or `pkgbuilds/*/omarchy-dev/` recipe, so the surveyed package command cannot yet build this source package.
- `./test/all` excludes native CTest, acceptance, packaging, fuzzing, benchmarks, and manual visual review.
- A reused VM with `--sync-omarchy` or `--sync-all` cannot prove a new native artifact, changed dependency, installed QML module, systemd unit, or package finalization. Those changes require a fresh ISO built from exact local `omarchy` and `omarchy-pkgs` revisions.

These are environment and integration dependencies for packaging and graphical proof, not reasons to delay headless contracts and isolated native components after the remaining G0 seams close.

## Contradictions and corrections

| Issue | Evidence | Resolution |
|------|----------|------------|
| Qt minimum differs | `A1` uses 6.5; `A3` CMake requires 6.8; both measurements use 6.11.2. | Do not freeze a numeric minimum. Packaging/CI evidence must select it. |
| “Trusted header” in worker-writable shared memory | `A3` proposes a trusted header in committed slots, while `A0` classifies all worker-originated metadata as `U2`. | Header contents remain untrusted. Trusted allocation metadata is stored separately by the host and used for validation. |
| Host maps slots read-only while worker writes them | `A3` correctly restricts the host mapping but does not eliminate concurrent worker mutation. | `B4` must define race-resistant publication and bounded copy/upload; read-only host mapping alone is not a security property. |
| A2's broker launches the worker directly | The spike combines launcher, broker, and demo authorization in one executable; `A0` separates logical lifecycle, supervisor, and broker authorities. | Treat this as a probe simplification. Production launch binding is supervisor-owned; broker consumes the authoritative binding. Initial physical co-location in `omarchy-plugin-host` is allowed. |
| A1 proposes one host executable while A0 names multiple trusted components | `A1` proposes `omarchy-plugin-host` as supervisor and broker; `A0` assigns distinct logical authorities. | No conflict if modules keep one-way ownership and tests. Physical process separation remains a later hardening option. |
| A3 integration gap | The renderer writes diagnostic PNGs, while the host module now proves only a sealed one-frame memfd validation/copy path and has no scene-graph uploader or live protocol. | The bounded G0 seam is satisfied. `C6` and `D2` own the fake and integrated live consumers, so the missing uploader/protocol is not a G0 blocker. |
| A1 disposable installation wording versus gate scope | A1's archive runs from staging but no clean disposable install exists. | The build/package seam is frozen from the staged archive. Exact repository package plus fresh-ISO installation is `F5`, not a G0 prerequisite. |
| Software environment variable differs | A1 CTest/run script uses `QT_QUICK_BACKEND=software`; A3 uses `QSG_RHI_BACKEND=software` and the programmatic graphics API selection. | Production uses the A3 pattern plus programmatic selection. The sandbox environment allowlist should omit inherited Qt variables and set one reviewed canonical set. |
| Software renderer versus arbitrary-QML goal | The boundary proof renders ordinary animated QML, but Qt's software adaptation omits `ShaderEffect` and particles and differs for transformed text. | Mark the initial reference profile incomplete. Do not claim full visual compatibility until a restricted-GPU profile passes its own boundary and fidelity gates. |
| Local Quickshell/Qt ABI mismatch | The external module loaded in Quickshell 0.3.0 built with Qt 6.11.0 against Qt 6.11.2 libraries, with a private-API mismatch warning; isolated Quickshell IPC also failed to initialize. | Dynamic import shape is proven for G0. ABI-matched packaged import and normal IPC are required at `F5`; the mismatch is not release evidence. |

## Deferred choices

These choices are outside the seam gate:

- schema-generated payload encoding, operation schemas, provider APIs, request cancellation, error taxonomy, and capability vocabulary;
- exact XDG stores, database versus journaled files, digest algorithm, state migration, retention, and audit redaction policy;
- surface-role limits, damage optimization, frame pacing defaults, multi-monitor policy, and resource budgets;
- custom `QSGTexture`/zero-copy rendering, GPU render-node access, and other pixel formats;
- accessibility, IME, drag and drop, popups/subwindows, cursor semantics, text selection, and non-rectangular input-region side channels;
- ordinary-window security-context Wayland exposure;
- provider isolation into separate processes;
- developer-mode source mounts, hot reload, inspector access, and legacy `unsafe.host-code` transition UX;
- plugin-to-plugin typed services and the secure-plugin versus trusted-host-extension threshold.

Deferred behavior is unsupported and denied in the first slice. It does not justify exposing a generic command, path, object, socket, display connection, or ambient environment variable.

## Downstream contract inputs

### `B0` native package skeleton

- One CMake/C++20 project producing the trusted host, private QML worker, embedded worker QML SDK, shared protocol code, and dynamic trusted bridge module.
- Link Qt Core/Gui/Qml/Quick; keep the numeric Qt minimum configurable until packaging evidence fixes it.
- Host/worker/protocol/bridge version reporting and atomic package upgrade.
- Worker outside ordinary PATH and unusable without inherited launch context.
- Authoritative native source at `native/plugin-runtime`, build output at `build/plugin-runtime`, CTest labels `unit`, `protocol`, `adversarial`, `property`, and `integration`, and an installed-artifact smoke in the fresh-ISO package path.
- A graphical-session-scoped `omarchy-plugin-host.service` and separate bridge client lifecycle; unit installation and enablement are package/VM-tested.

### `B1` manifest and lifecycle contract

- Canonical plugin id, recorded source identity, commit, tree digest, manifest digest, requested-capability fingerprint, activated revision, worker role, and generation are distinct fields.
- Activation/grant changes are atomic; source is immutable; candidate health does not replace the old revision until commit.
- Lifecycle manager, not worker or manifest, owns identity and activation.

### `B2` capability, grant, and audit contract

- Channel identity is an input from the supervisor binding, never a request field.
- Grant checks remain per operation and handles bind to plugin, revision policy, generation, scope, and lifetime.
- Audit accepts authoritative producer identity and redacted bounded metadata, never direct worker records.

### `B3` broker wire contract

- Preserve the frozen 40-byte `OMPL` envelope, packet boundary, role-specific payload limits, independent three-endpoint handshake rules, launch generation, correlation id, credentials requirement, and default descriptor denial.
- Add generated message schemas, request ids, typed errors, cancellation, deadlines, concurrency/rate limits, negotiation failure, events, and golden malformed fixtures.
- Apply the common envelope independently to FD 3 control, FD 4 broker RPC, and FD 5 render/input. Define per-role message sets, state machines, budgets, close behavior, and cross-channel generation/sequence rules. Define the separate trusted daemon-to-bridge handshake and descriptor messages; direct worker-to-bridge routing is invalid.

### `B4` render, surface, and input contract

- Software offscreen `QQuickRenderControl`, fixed premultiplied RGBA, host-created two-slot shared memory, authenticated notification, trusted allocation metadata, and bridge-owned surface/input policy.
- Specify complete buffer layout and limits, race-resistant slot state/sequence protocol, memory ordering, safe copy/upload, descriptor transfer, reconnect, stale generation, malformed frame, producer death, and last-valid-frame behavior.
- Treat all shared pages and worker metadata as untrusted even when mapped read-only in the host.

### `B5` sandbox and resource policy

- Construct an environment from an allowlist; set offscreen/neutral/software Qt values before application creation.
- New namespaces; no normal Wayland/X11, D-Bus, network, agent, credential, device, host runtime, or real home access.
- Read-only activated revision; private scratch/runtime; only explicitly granted state access.
- Preserve only fixed worker FDs 3/4/5 and explicitly schema-authorized shared-memory descriptors; close everything else. Control never accepts descriptors, broker defaults to none, and render/input accepts only typed host-created buffers.
- pidfd-backed process identity, cgroup limits, bounded output/restart, and full process-tree teardown.
- Run the daemon as a graphical-session-scoped systemd user service; define systemd restart limits, per-generation child scopes/cgroups, session-stop teardown, shell-absence behavior, and bridge reconnection without passing ambient manager environment into workers.

### `B6` tests, fakes, and malicious probes

- Reuse the envelope vectors, forged identity case, oversize rejection, offscreen animated QML scene, fixed alpha dimensions, and worker-direct-launch denial.
- Add missing credentials, wrong PID/UID, descriptor smuggling, non-`HELLO` first packet, bad magic/version/type/flags/length, truncation, replayed generation, shared-memory mutation races, malformed frames, producer crash, and shell/bridge survival.
- Deterministic native cases run in labeled CTest; fixtures/corpora live under `test/plugin-security/`; installed service-manager, user-bus, compositor, and package-permission attacks run in disposable-VM acceptance.

### `C5` worker and `C6` trusted bridge

- `C5` implements the measured software lifecycle and consumes only supervisor-issued source, geometry, environment, and descriptors.
- `C6` implements a narrow native `QQuickItem` against fake validated surfaces. It owns pixel upload and input transport but no plugin parsing, grant state, or general broker dispatch.
- They build against `B4` fixtures and must not require each other's live implementation.

## Checkpoint evidence rerun

The synthesis reran the available proofs on 2026-08-28:

- Native build: GCC 16.2.1 and Qt 6.11.2 configured and built the C++20/QML target in `/tmp`; the offscreen binary reported `QQuickRenderControl linked; QML module loaded`.
- Private channel: the focused build, forged-identity assertion, self-test, and CTest passed when run in the ordinary host execution context. The managed filesystem sandbox rejected `SO_PASSCRED` with `EPERM`; rerunning outside that additional tool sandbox passed. This is evidence about the test harness environment, not a reason to weaken the plugin sandbox design.
- Bubblewrap identity: the ordinary, occupied-reserved-FD, closed-stdin, closed-stdout, and closed-stderr modes passed outside the managed command sandbox. Bubblewrap's reported outer child PID matched `SCM_CREDENTIALS.pid`; the worker observed PID 1 and UID 0 internally; no unexpected descriptor or standard-FD alias survived; role substitution and a fork descendant were denied on all three endpoints; each receive was pidfd-lifetime-gated; a closed-pidfd injection rejected a queued correct-credential packet; the pre-pidfd cleanup fixture reaped through a bounded nonblocking loop; an inherited-endpoint holder produced no acceptable post-exit traffic; and the worker pidfd became readable on exit.
- Render transport: six distinct 320 × 96 premultiplied RGBA frames rendered both normally and with `WAYLAND_DISPLAY` and `DISPLAY` removed. Each frame was 122,880 bytes; the two rerun averages for polish/sync/render were 0.113 ms and 0.164 ms, excluding the deliberate animation wait and PNG encoding.
- External host module: `Omarchy.PluginHost` installed with the standard URI-derived layout, dynamically loaded into a generic engine that did not link the module, and instantiated in an isolated Quickshell 0.3.0 process. Quickshell's default import list includes `/usr/lib/qt6/qml`, so no user-controlled import path is needed in the package. The local Quickshell/Qt patch mismatch and isolated IPC warning remain non-release caveats owned by `F5`.
- Fixed memfd consumer: both host-module CTests and both isolated installed-prefix smokes passed. The producer exited before import; the module copied the sealed 8 × 4 premultiplied RGBA frame into a 128-byte host-owned image, rejected malformed metadata, and retained the valid SHA-256 digest.
- A1's recorded `makepkg` result produced a main and debug archive, with the main probe in `/usr/bin`, direct Qt Core/Gui/Qml/Quick dependencies, and no RPATH/RUNPATH. This closes the G0 package-shape seam; clean installed-VM execution remains `F5`.
- A4 confirms existing CLI/shell/acceptance entry points and assigns native CTest, adversarial, fuzz/property, benchmark, package, VM, and visual evidence independently. It also confirms that the current workspace lacks `omarchy-iso` and an authoritative sibling `omarchy-pkgs` recipe, so installed proofs are unavailable here.

## Gate closure checklist

`G0` closes only when all items below have named evidence:

- [x] Exact trust, process, channel, filesystem, credential, handle, lifecycle, and policy-authority map (`A0`).
- [x] Local C++20/Qt native build, QML module, offscreen execution, install rule, and Arch archive (`A1`).
- [x] Historical private inherited endpoint, forged payload identity denial, packet boundary, and truncation evidence (`A2` base fixture).
- [x] Frozen 40-byte outer envelope conformance across FD 3 control, FD 4 broker RPC, and FD 5 render/input (`A2` envelope follow-up).
- [x] Animated QML within the incomplete offscreen software profile and with no display connection (`A3 renderer`).
- [x] External public-API `Omarchy.PluginHost` module dynamically imported by a generic engine and isolated Quickshell (`A3 host module`).
- [x] Bounded fixed-size memfd validation/copy probe through the native host module, including malformed metadata denial, producer exit, and last-valid-frame preservation.
- [x] Bubblewrap FD 3/4/5 launch tuple, normalized standard FDs, kernel-credential plus fail-closed pidfd-lifetime binding including invalid-pidfd injection, role-substitution and descendant denial, post-exit holder containment, collision-safe unrelated-FD closure, and fully bounded teardown before and after pidfd acquisition.
- [x] Graphical-session systemd daemon lifetime and three-endpoint worker-to-daemon topology design frozen.
- [x] Exact test entry points, fixture/results locations, test-layer ownership, package/VM boundary, and environment gaps (`A4`).
- [x] A4 reconciliation recorded in this document.

`G0` authorizes the `B*` contract/scaffold fan-out against fakes. It does not claim a packaged, integrated, visually complete, or production-secure runtime; those claims remain gated by `C*` through `F*`, culminating in `G4`.
