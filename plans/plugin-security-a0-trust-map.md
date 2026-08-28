# A0 Plugin Trust-Boundary and Process Map

## Purpose and status

This document is the Wave 0 `A0` artifact from [`plugin-security-work-graph.md`](plugin-security-work-graph.md). It maps the current plugin lifecycle to exact repository paths, then assigns one proposed owner to every trusted component, cross-boundary channel, credential, filesystem object, policy decision, startup transition, and teardown transition in the secure schema-v2 model.

The proposed component names and logical stores below are architectural labels, not frozen executable names or install paths. Subsequent `G0` work selected a graphical-session-scoped `omarchy-plugin-host` systemd user service, three role-specific worker endpoints, and a public-API native bridge inside Quickshell. Later contract nodes still own the domain schemas, concrete filesystem layout, live shared-memory publication algorithm, and daemon-to-bridge protocol.

## Trust classes

| Class | Meaning | Examples |
|------|---------|----------|
| `T0 user authority` | A deliberate user or administrator decision. Code cannot manufacture this authority. | Permission selection, state-retention choice, developer-mode opt-in |
| `T1 security authority` | Trusted Omarchy code that owns or enforces policy and handles ambient session authority. A compromise defeats the plugin boundary. | Lifecycle manager, grant store, broker, supervisor, trusted surface host |
| `T2 trusted integration` | Trusted code with narrowly assigned session access, but no authority to grant a plugin additional capabilities. | Broker operation providers, permission UI, audit inspector |
| `T3 trusted data` | Omarchy-owned persistent or runtime state that untrusted code cannot modify directly. | Activated revision pointer, grants, audit records, worker-to-plugin binding |
| `U0 untrusted source` | Bytes fetched from or edited by a plugin publisher before complete validation and activation. | Git checkout in staging, manifest, bundled executable |
| `U1 confined plugin` | Activated plugin code and its descendants running under the schema-v2 sandbox. It may render and request operations but is never a policy authority. | QML UI worker, helper worker, plugin JavaScript and assets |
| `U2 untrusted protocol data` | Messages, pixels, semantic trees, file names, URLs, and other values received from a plugin. Trusted recipients validate and bound them before use. | Broker request, frame metadata, accessibility update |
| `L0 legacy full trust` | Schema-v1 third-party code explicitly admitted into the host process. It is outside the secure model and has indivisible `unsafe.host-code` authority. | Current third-party QML after explicit legacy enablement |

First-party QML remains trusted application code. The fact that first-party and third-party manifests currently share a registry contract must not imply that they share a future trust class.

## Current implementation map

### Current process and authority topology

```text
uwsm / Hyprland session
  |
  | default/hypr/autostart.lua invokes omarchy-launch-shell
  v
bin/omarchy-launch-shell (restart loop, inherited user session environment)
  |
  +-- systemd-cat -t omarchy-shell
        |
        v
      quickshell -n -p "$OMARCHY_PATH/shell"
        one process + one QML engine + normal session Wayland/DBus/environment
        |
        +-- shell/shell.qml                              [trusted host]
        +-- shell/services/PluginRegistry.qml            [trusted registry]
        |     +-- bash/find/cat manifest scan children
        |     +-- inotifywait recursive watcher child
        +-- first-party plugin QML                       [trusted]
        +-- schema-v1 third-party bar/service/panel/QML  [same authority as host]
        +-- plugin-created Process children              [same logged-in user]

user/desktop/CLI caller
  |
  +-- bin/omarchy-shell -> qs ipc -> Quickshell IpcHandler targets
  +-- bin/omarchy-plugin-* -> filesystem/git + shell IPC
```

There is no isolation boundary between a loaded schema-v1 plugin and `omarchy-shell`. QML object ownership, process credentials, environment, open session connections, available imports, and crash fate are shared.

### Current component inventory

| Component | Exact implementation | Startup and responsibilities | Trust and ambient access | Current boundary failure |
|-----------|----------------------|------------------------------|--------------------------|--------------------------|
| Session launcher | `default/hypr/autostart.lua`, `bin/omarchy-launch-shell` | Hyprland autostart invokes the launcher. It runs `systemd-cat -t omarchy-shell -- quickshell -n -p "$OMARCHY_PATH/shell"`, restarts non-clean failures up to a bounded rate, and stops on session teardown. | Trusted; inherits the user session environment and compositor connection context. | Every plugin loaded by the child inherits the shell's authority and failure domain. |
| Shell host | `shell/shell.qml` | Creates `PluginRegistry`, `BarWidgetRegistry`, and application services; reads default and user `shell.json`; loads bars, services, panels, overlays, menus, and widget components. | Trusted long-lived Quickshell process with normal user credentials, environment, Wayland access, Quickshell modules, and session facilities. | Third-party QML is evaluated in its engine and receives reachable host objects. |
| Runtime registry | `shell/services/PluginRegistry.qml` | Creates the user plugin directory, scans manifests, validates part of schema v1, computes enabled state from `shell.json`, watches local source, and mutates enablement. | Trusted QML object in the host engine; uses `Quickshell.Io.Process` and can write configuration through the injected mutator. | Path checks constrain the initial entry-point string, not the behavior of loaded code. Runtime validation is weaker than CLI validation. |
| Manifest scanner | `PluginRegistry.qml` functions `rescan`, `parseScanOutput`, and `scanProcess` | A `bash -c` child uses `find`, `cat`, and sentinel-delimited stdout to enumerate first-party and third-party manifests. | Child of the trusted shell with the shell environment and filesystem access. Manifest bytes and paths are untrusted inputs. | No immutable content identity separates discovery from later execution; parsing uses an ad hoc text envelope. |
| Local source watcher | `PluginRegistry.qml` property `localPluginWatcher`; `shell.qml` functions `reloadPlugins` and `finishPluginReload` | Runs recursive `inotifywait` on `~/.config/omarchy/plugins`; non-hidden, non-`.git` writes schedule a 150 ms unload, QML cache clear, rescan, and reload. | Trusted host child watching a user-writable live code tree. | Managed update writes can cause pre-validation execution. Any direct local write hot-reloads code with full host authority. |
| Plugin installer | `bin/omarchy-plugin-add` | Clones with Git into `~/.config/omarchy/plugins/.add.tmp.$$`, validates, checks id collision, moves it to `~/.config/omarchy/plugins/<id>`, rescans, and optionally enables. | User-invoked trusted shell script; Git has network and user-level filesystem access. Fetched bytes are untrusted. | The installed checkout becomes the live executable tree. `--yes` skips review but currently does not automatically enable unless `--enable` is also supplied. There is no content-addressed activation boundary. |
| Plugin updater | `bin/omarchy-plugin-update` | Fetches `origin HEAD`, optionally displays `HEAD..FETCH_HEAD`, fast-forwards the live checkout, validates afterward, resets to `ORIG_HEAD` on failure, then requests a rescan. | User-invoked trusted script; Git operates directly in live source. | Files become observable by the watcher before validation or rollback completes. Existing code and prospective code are not distinct revisions. |
| Plugin remover | `bin/omarchy-plugin-remove` | Reads current enabled state by IPC, disables first, deletes a Git checkout or symlink, or moves a hand-created tree to a timestamped hidden backup, then rescans. | User-invoked trusted script with destructive access to the user plugin directory. | Runtime teardown is an eventual host-object unload, not worker termination and handle invalidation. No separately owned plugin state or grants exist. |
| CLI validator | `bin/omarchy-plugin-validate` | Validates schema version 1, required fields, ids, entry-point keys and files, entry-point traversal, kinds, bar placement, and symlinks outside `.git`. | Trusted parser over `U0` bytes. | Validation is not activation, does not canonicalize an immutable tree, and cannot constrain QML behavior. Git internals and total tree resource bounds remain outside this check. |
| Enable/disable commands | `bin/omarchy-plugin-enable`, `bin/omarchy-plugin-disable`; `PluginRegistry.qml` function `setEnabled` | Call the shell IPC target, which mutates `~/.config/omarchy/shell.json`. A third-party id is enabled by `bar.id`, a bar layout entry, or `plugins[]`; first-party non-bar plugins default on unless disabled. | Trusted CLI and host registry. `shell.json` is user-writable configuration, not a protected grant database. | Enablement immediately authorizes all host-process behavior. No requested/granted permission distinction exists. |
| Full bar loader | `shell/shell.qml` property `pluginBarLoader` and function `configureBar` | Loads the third-party bar URL asynchronously and injects `omarchyPath`, `shell`, `manifest`, `barWidgetRegistry`, `pluginRegistry`, and `barConfig`. | Plugin becomes `L0`, inside the host engine. | It can replace the bar, traverse trusted objects, create privileged surfaces, and crash the host. |
| Service loader | `shell/shell.qml` functions `ensureService`, `_syncServices`, and `unloadPluginServices` | Uses `Qt.createComponent` and `createObject` in an invisible host item; injects host and registry references; starts enabled services at shell startup/rescan. | Plugin becomes `L0`; service persists while enabled. | Background arbitrary code receives ambient session authority without a displayed surface. |
| Panel/overlay/menu loader | `shell/shell.qml` `panelEntries` and `Instantiator` delegate | Creates a `Loader` for every enabled matching manifest. Loads on summon or continuously when `keepLoaded`; injects host references and the matching service. | Plugin becomes `L0`; plugin QML can own Quickshell windows and layer-shell surfaces. | Host does not own or constrain surface role, placement, focus, z-order, or input. |
| Bar-widget loader | `shell/shell.qml` functions `syncPluginWidgets` and `loadPluginWidget`; `shell/services/BarWidgetRegistry.qml`; `shell/plugins/bar/Bar.qml` | Creates a QML `Component` from the plugin URL, registers it, and lets the active bar instantiate the object in a layout slot. | Plugin becomes `L0` inside the bar and shell object graph. | A visual slot is not an authority boundary; arbitrary component code executes in the host. |
| Shell IPC | `bin/omarchy-shell`; `IpcHandler` objects in `shell/shell.qml` and plugins | The wrapper calls `qs ipc -n -p "$OMARCHY_PATH/shell" call`. It selects the session Wayland display when absent. Shell and plugin `IpcHandler`s expose methods to local callers. | Quickshell owns the IPC endpoint in its instance runtime directory. Calls are associated with a target and method, not a secure-plugin identity or grant. | A loaded plugin may register IPC and call host/plugin methods. This channel is not suitable as the schema-v2 broker channel. |
| Logging | `bin/omarchy-launch-shell` via `systemd-cat`; QML console output | Sends the combined shell and plugin log stream to the journal under `omarchy-shell`. | Trusted logging path receives untrusted plugin-controlled strings. | No per-plugin attribution, output budget, or sensitive-payload policy exists. |

### Current filesystem objects

| Path | Current writer | Current reader/executor | Security significance |
|------|----------------|-------------------------|-----------------------|
| `$OMARCHY_PATH/shell/plugins/` | Omarchy package/update path | `PluginRegistry.qml`, shell loaders | First-party trusted plugin source. |
| `~/.config/omarchy/plugins/.add.tmp.$$` | `bin/omarchy-plugin-add` and Git | CLI validator | Temporary untrusted clone. It is hidden from the runtime scan and watcher plugin-id mapping, but remains under the watched parent. |
| `~/.config/omarchy/plugins/<id>/` | Git updater, user/editor, clone command | Registry and host QML engine | Mutable source, Git metadata, manifest, assets, and executable code share one live tree. |
| `~/.config/omarchy/plugins/.<id>.bak.<timestamp>` | Remove command for non-Git plugins | User only by convention | Recoverable source backup; hidden from discovery. |
| `~/.config/omarchy/shell.json` | Shell `FileView`, plugin enable/disable and bar commands, user/editor | Shell and registry | Layout, settings, and enabled state share one user-editable document. It is not a security grant store. |
| `$OMARCHY_PATH/config/omarchy/shell.json` | Omarchy package/update path | Shell fallback/default loader | Trusted default configuration, not active permission state. |
| Quickshell instance runtime directory | Quickshell | `qs ipc` callers and Quickshell | Shell IPC and transient logs/state. The concrete path is owned by Quickshell and is not defined in this repository. |
| User journal | `systemd-cat` | User/journal tools | Shell and plugin output are combined under one tag. |

### Current credentials, handles, and sockets

The repository does not filter the Quickshell environment or descriptors before loading plugins. A plugin runs in the already-connected process, so the relevant authority is broader than environment variables alone.

| Authority or handle | Current holder | Plugin exposure |
|---------------------|----------------|-----------------|
| Logged-in UID/GID and user-readable filesystem | Quickshell process | Identical process credentials; arbitrary reads/writes through QML APIs or child processes. |
| Normal Wayland connection and compositor globals | Quickshell/Quickshell modules | Shared process and imports allow creation of windows and privileged shell surfaces exposed to that client. |
| Session D-Bus address/socket | Session environment and Qt/Quickshell modules | Not removed; plugin QML or child processes may connect. |
| Shell environment, including `HOME`, `OMARCHY_PATH`, `XDG_RUNTIME_DIR`, display variables, and any inherited secrets | Quickshell process | `Quickshell.env` and child-process inheritance expose it. |
| Agent or credential sockets such as SSH/GPG agents when present | Session environment/runtime directory | Not removed or namespaced. Plugin code can use available APIs or children to connect. |
| Network namespace | Host session | Plugin and child processes have ordinary network reachability. |
| Quickshell IPC endpoint | Quickshell instance | Plugin may register targets in-process; external callers are not bound to a plugin grant. |
| Host QML object references | Direct property injection from `shell.qml` | `shell`, `manifest`, `pluginRegistry`, `barWidgetRegistry`, `bar`, and sometimes `service` are intentionally reachable. |

Exact inherited secret names vary by user session and must not become an allowlist inferred from this table. Schema-v2 workers need a newly constructed environment and explicit descriptor allowlist.

### Current lifecycle sequence

#### Shell startup

1. `default/hypr/autostart.lua` runs `omarchy-launch-shell`.
2. `bin/omarchy-launch-shell` starts Quickshell through `systemd-cat`, monitors its PID, and restarts abnormal exits while the compositor remains alive.
3. `shell/shell.qml` creates registries and loads `shell.json` plus defaults.
4. `PluginRegistry.qml` creates `~/.config/omarchy/plugins`, starts recursive `inotifywait`, and scans first-party and third-party manifests with a Bash child.
5. `scanFinished` causes the host to instantiate enabled services, compute panel entries, and create/register enabled bar-widget components. The selected full bar is loaded through its `Loader`.
6. Panels, overlays, and menus load on demand unless `keepLoaded` is set.

#### Reload, disable, and shutdown

1. A local source event or explicit `rescanPlugins` begins a reload.
2. The host destroys panels and services, unregisters plugin widget components, clears the QML component cache, and scans again.
3. Disablement mutates `shell.json`; reactive registry changes cause the corresponding objects to unload.
4. Shell termination kills the single Quickshell process; children created by plugins are not assigned a repository-defined plugin cgroup or teardown contract.

## Proposed secure topology

### Process graph and ownership

```text
T0 user
  |
  +-- trusted permission UI / CLI -------------------------------+
                                                               |
                                                               v
T1 lifecycle manager <----> T3 revision/activation/grant state
  |  validates, stages, activates, rolls back, revokes
  |
  +-- T1 omarchy-plugin-host systemd user daemon ----------------+
  |     owns supervisor, broker, identity, cgroup, FDs, health     |
  |                                                              |
  |    bwrap + systemd resource scope                             |
  |       |                                                       |
  |       v                                                       |
  |     U1 QML/helper worker                                      |
  |       +-- FD 3 control ------------------------------------+  |
  |       +-- FD 4 broker RPC ---------------------------------+  |
  |       +-- FD 5 render/input -------------------------------+  |
  |                                                           |  |
  |    T1 broker core <----------------------------------------+  |
  |       | structured calls                                     |
  |       v                                                       |
  |    T2 operation providers                                    |
  |       +-- session APIs/files/network/credentials              |
  |                                                              |
  |    separate authenticated trusted bridge session              |
  |       v                                                       |
  |    T1 native bridge inside omarchy-shell                       |
  |       +-- host-owned Wayland surfaces and bounded input        |
  |                                                              |
T3 redacted audit <-----------------------------------------------+

Optional ordinary-window lane only:
  U1 window worker -> dedicated compositor security-context socket
  (never the normal session Wayland socket)
```

| Proposed component | Trust | Sole authority and responsibility | Must not own |
|--------------------|-------|-----------------------------------|--------------|
| Lifecycle manager | `T1` | Validate staged trees; record origin and digests; install immutable revisions; coordinate permission selection; atomically switch activation plus capability fingerprint; retain rollback metadata; initiate removal. | It must not parse or render plugin QML and must not infer a grant from a manifest or `--yes`. |
| Grant authority/store | `T1`/`T3` | Store the user's scoped grant, denial, gesture, revision fingerprint, and revocation state. Answer authoritative grant queries. | Plugin source, `shell.json`, worker SDK code, and manifest declarations are not grant authorities. |
| Plugin supervisor | `T1` | Bind canonical plugin id and activated revision to a launch; construct the Bubblewrap sandbox; allocate inherited channels and handles; create resource limits/cgroup; health-check; restart within policy; terminate the complete process tree; invalidate runtime identity. | It must not grant capabilities or accept a plugin-supplied identity. |
| Capability broker core | `T1` | Authenticate a request from the supervisor-created channel binding; validate framing, version, type, size, rate, scope, gesture, and current grant on every request; issue/cancel opaque handles; dispatch only registered operations. | It must not execute arbitrary plugin-supplied shell text, trust SDK-side checks, or treat possession of a channel as a grant. |
| Broker operation provider | `T2` | Perform one reviewed domain operation using only the authority required for that provider; validate operation-specific values; redact audit metadata. | It cannot broaden a grant, dispatch another provider generically, or return ambient host paths/credentials when an opaque handle suffices. |
| Trusted surface host/bridge | `T1` | Own compositor surfaces, placement, dimensions, z-order, focus policy, exclusive zones, lock-screen exclusion, frame budgets, input routing, plugin identity treatment, inspection, and termination affordances. Validate every frame and surface message. | It does not evaluate third-party QML, decide general capability grants, or forward global input. |
| QML render worker | `U1` | Evaluate arbitrary plugin QML in its own engine; render into bounded buffers; consume assigned input/theme/lifecycle events; request broker operations. | No ambient home, network, D-Bus, normal Wayland, devices, agents, host QML objects, grants, or policy decisions. It cannot choose its plugin id. |
| Helper worker | `U1` | Run declared plugin computation under the same plugin identity and resource policy, using structured channels. | No host installer, ambient executable dispatch, privilege gain, or authority beyond separately granted broker calls. |
| Permission UI/CLI | `T2`, expressing `T0` | Display recorded origin, revision, required and optional requests, resource scopes, permission deltas, and consequences; submit explicit user decisions to the grant authority. | It cannot let plugin-rendered pixels impersonate the trusted prompt, and `--yes` cannot mean grant-all. |
| Audit writer/inspector | `T1` writer, `T2` reader | Append and query bounded, redacted records for lifecycle, requests, decisions, handles, revision changes, and grant changes. | Worker-provided payloads and secrets must not be logged verbatim. Audit storage is not plugin-readable. |
| Legacy host loader | `L0` | Load schema-v1 third-party QML only after the indivisible unsafe policy permits it. | It cannot claim granular enforcement or share schema-v2 grants. |

The trusted surface bridge is a narrow public-API native QML module loaded into `omarchy-shell`. It communicates only with `omarchy-plugin-host` over a separate authenticated trusted session; workers never connect to it directly. The bridge remains a security authority because it consumes untrusted frames and controls compositor surfaces, even though the module is not a separate process boundary.

### Cross-boundary channel map

| Channel | Producer -> consumer | Bootstrap and identity | Data and authority | Required enforcement owner |
|---------|----------------------|------------------------|--------------------|----------------------------|
| Lifecycle control | Trusted CLI/UI -> lifecycle manager | Local same-user control endpoint or direct invocation; exact transport unresolved. The manager derives the local user context, never a plugin identity supplied in payload. | Install/update/enable/disable/revoke/remove requests and explicit grant selections. | Lifecycle manager validates state transitions; grant authority records only explicit selections. |
| Worker control | Supervisor <-> worker | Private Unix `SOCK_SEQPACKET` endpoint created before sandbox entry and inherited as FD 3. The supervisor's launch record binds it to plugin id, revision digest, worker role, launch generation, outer PID/UID/GID, and pidfd. | At most 4 KiB of ready/health, shutdown, cancellation, lifecycle, and negotiated role-protocol messages. Possession conveys launch provenance only, not capabilities. Descriptors are forbidden. | Supervisor bounds messages, deadlines, generations, credentials, descriptor quarantine, and shutdown. |
| Broker RPC | Worker <-> `omarchy-plugin-host` broker | A distinct private `SOCK_SEQPACKET` endpoint inherited as FD 4 and bound to the same launch tuple. No request field may override channel identity or endpoint role. | At most 64 KiB of typed request/response/error/event messages and opaque handle identifiers. Descriptors are forbidden in version 1. | Broker core enforces the common envelope, role state, current grants, correlation bounds, and descriptor cleanup on every request. |
| Frame transport | Worker <-> `omarchy-plugin-host` render endpoint, then daemon <-> trusted bridge | FD 5 is the worker's distinct authenticated render/input endpoint. The host creates one fixed-capacity memfd containing two writable streaming slots and transfers it only in the typed host-to-worker allocation message. The completed sealed immutable memfd import is a bounded proof, not the production streaming protocol. | At most 16 KiB of metadata per packet; pixels and slot headers remain `U2`. Metadata includes surface id, launch and surface generations, size, stride, format, damage, sequence, and timing. No buffer address or path is authority. | Daemon and trusted bridge cap surfaces, dimensions, bytes, formats, rates, in-flight buffers, generations, and damage before display; the live writable-slot ownership/sequence algorithm remains a `B4` contract. |
| Input/presentation | Trusted bridge -> daemon -> worker | The bridge uses its separate authenticated daemon session; the daemon validates the surface and relays bounded events over worker FD 5. There is no worker-to-Quickshell endpoint. | Bounded local coordinates, buttons/keys permitted by role, focus, resize, DPR, theme tokens, locale, visibility, and frame scheduling. | Trusted host derives events from its surface and policy. It never forwards global input, trusted-prompt input, or ungranted focus. |
| Semantic side channel | Worker -> trusted surface host/accessibility adapter | Same surface identity and generation as frame transport. Protocol not designed yet. | Accessibility tree, cursor, popup, IME, text-selection, drag/drop, and input-region semantics are all `U2`. | Trusted host validates tree size/depth/rate and maps only supported semantics. Unsupported messages fail closed. |
| Audit events | Lifecycle/supervisor/broker/host -> audit writer | Trusted internal interface; each producer supplies its own authoritative component identity. | Redacted decision and health metadata. | Audit writer bounds records and rejects worker-direct writes. |
| Provider dispatch | Broker core -> operation provider | In-process typed interface or private trusted IPC. Exact split unresolved. | Already authenticated request plus authoritative plugin/grant context. Sensitive credentials and host handles remain provider-side. | Provider revalidates domain-specific bounds; broker remains grant authority. |
| Ordinary-window Wayland | Dedicated worker -> compositor | Supervisor passes a per-plugin `security-context-v1` connection only for a granted ordinary-window role and only after compositor policy is proven. | Restricted Wayland globals and attributed client identity. | Compositor protocol policy plus supervisor. Absence of adequate restrictions means no connection is passed. |
| Existing shell IPC | Local callers -> `omarchy-shell` | Existing `qs ipc` path. | Trusted shell commands and schema-v1 compatibility. | It remains outside broker identity. Secure plugins must not receive it as their authority channel or be allowed to register arbitrary global targets. |

The channel contract must treat EOF, peer death, invalid generation, descriptor-count mismatch, malformed messages, oversized messages, and version mismatch as termination or typed denial conditions. A reconnect never inherits stale handles or the old worker generation.

### Proposed secrets and opaque handles

| Secret or handle | Creator and holder | Worker representation | Revocation and leakage rule |
|------------------|--------------------|-----------------------|-----------------------------|
| Worker identity binding | Supervisor launch record | Not a plugin-writable field; implicit in inherited channel | Dies with channel/generation. Reconnect requires a new supervised launch. |
| Revision identity | Lifecycle manager records origin, commit, tree digest, manifest digest, and capability fingerprint | Read-only non-secret metadata may be exposed | Worker cannot select or mutate it. Activation pointer changes atomically. |
| Grant record | Grant authority | Capability availability and narrowed non-sensitive scope only | Checked per call; revocation immediately blocks new calls and cancels/invalidates affected handles. |
| User-selected file/directory | Trusted portal/provider | Random opaque handle id, never an ambient host path unless the operation explicitly requires displaying it | Bound to plugin id, grant, resource, mode, revision policy, and lifetime; revocable and non-transferable across plugins. |
| Service credential/token | Credential provider/keyring | Opaque account or credential handle, or no handle when the provider can compose the whole operation | Raw secret stays broker/provider-side. Revocation and account removal invalidate it. |
| Gesture proof | Trusted surface host/broker | Short-lived opaque token bound to plugin, surface, event class, and allowed operation | Single-use or tightly time-bound; cannot be self-issued or replayed on another channel. |
| Frame buffer FD | Trusted host/supervisor allocation policy | Mapped buffer for one negotiated surface/generation | Hard byte/in-flight limits; close on replacement, worker death, surface destruction, or protocol fault. Never interpreted as a general file handle. |
| Private storage | Storage provider | Structured storage API, not host path | Namespace and quota bound to canonical plugin identity. Retention on removal requires a `T0` decision. |
| Provider result handle | Operation provider | Typed opaque id | Bound to originating channel generation, plugin, operation family, and expiry; stale/foreign use is denied and audited. |

No bearer token supplied in a manifest, environment variable, command-line argument, or filesystem file should establish plugin identity. Inherited FD association and supervisor-owned process metadata are the root runtime identity.

### Proposed filesystem ownership

Concrete paths are intentionally deferred to `B1`, `B2`, `B5`, and packaging work. The following logical stores and ownership splits are required regardless of their final XDG locations.

| Logical object | Trust | Writer | Runtime mount/read policy | Required property |
|----------------|-------|--------|---------------------------|-------------------|
| Network-constrained fetch staging | `U0` | Dedicated fetch/install step | Never mounted into an active worker; not watched by the shell | No hooks, builds, dependencies, or plugin code execute; enforce tree size, count, type, and time limits. |
| Validated immutable revision store | `T3` containing untrusted bytes | Lifecycle manager only | Exactly one activated revision is bind-mounted read-only into a worker | Content-addressed; no live Git mutation; origin and all digests recorded. |
| Activation record | `T3` | Lifecycle manager transaction | Read by supervisor and discovery; never writable/mounted to worker | Atomically binds plugin id to revision digest and request fingerprint, with previous revision retained for rollback. |
| Grant store | `T3` | Grant authority only | Broker reads authoritative state; not mounted to worker | Separate from source and `shell.json`; transactional with activation decision where required. |
| Private persistent state | Plugin-confidential data mediated by `T1/T2` | Storage provider on validated requests | Prefer API access rather than a broad mount; if mounted, only the one plugin namespace and only when granted | Per-plugin isolation, quota, retention policy, backup semantics, and revocation behavior. |
| Ephemeral scratch/runtime | `U1` | Worker | Private `/tmp`, synthetic home, private runtime directory | Destroyed on teardown; contains no host runtime sockets. |
| Cache | `U1` mediated by trusted quota policy | Worker/provider | Separate from source and durable state | Disposable, quota-bound, and not authority-bearing. |
| Audit store | `T3` | Audit writer | Inspector reads redacted views; never mounted to worker | Bounded retention, integrity, per-plugin attribution, no sensitive payloads. |
| Developer source mount | `U0/U1` | User/editor | Only explicit developer runtime or `unsafe.host-code`; never normal managed activation | Visibly non-immutable and isolated from managed revision semantics. |

The current `~/.config/omarchy/plugins/<id>` layout may remain as a compatibility or developer-facing location, but it cannot simultaneously be a mutable Git checkout, an authoritative activation record, and executable schema-v2 source.

## Policy-authority matrix

| Decision | Requester/input | Sole authority | Enforcement point | Fail-closed result |
|----------|-----------------|----------------|-------------------|--------------------|
| Whether source bytes form an installable revision | Publisher bytes and manifest | Lifecycle manager against schema/tree policy | Before revision-store insertion | Remain staged or reject; never discover or execute. |
| Canonical plugin identity | Validated manifest plus recorded source identity | Lifecycle manager | Install and every activation | Reject collision, reserved identity, origin substitution, or digest mismatch. |
| Whether a capability is requested | Manifest | Manifest validator records the request only | Install/update diff | Undeclared operation is unavailable; request never implies grant. |
| Whether and how a capability is granted | Explicit `T0` selection | Grant authority | Persisted grant transaction | Missing required grant keeps revision installed but disabled/staged. |
| Whether a broker call may execute | Authenticated channel, current grant, request scope, gesture | Broker core | Every request and continuation | Typed denial; repeated abuse may terminate worker. |
| Whether a surface may exist | Manifest request, grant, host role policy | Trusted surface host using lifecycle/grant context | Surface creation and every mutation | No surface or retain last valid surface state. |
| Surface position, z-order, focus, lock visibility, monitor, maximum size/rate | Role invariant plus selected scope | Trusted surface host | Every frame/input/surface transition | Clamp only where semantics are unambiguous; otherwise deny/terminate the surface. |
| Worker identity and revision generation | Activated state | Supervisor | Channel creation, launch, and message dispatch | No channel/launch, or terminate stale peer. |
| Resource limits and restart | Omarchy resource policy | Supervisor | Sandbox/cgroup launch and health loop | Stop process tree; bounded retry; leave host alive. |
| Update activation | Valid revision, health result, permission delta, explicit selections | Lifecycle manager transaction | Atomic activation switch | Old revision and grants remain active. |
| Revocation effect | `T0` decision or trusted administrative policy | Grant authority plus supervisor/broker | Immediately at store, broker, handle, and process boundary | Block/cancel operation; terminate worker when required by capability or boundary. |
| Plugin removal and state retention | `T0` decision | Lifecycle manager | Stop, detach activation, delete grants, then apply retention choice | Worker stops first; ambiguous state is retained, not silently destroyed. |
| Legacy schema-v1 execution | Explicit indivisible unsafe choice | Legacy policy owned by lifecycle/host | Before in-process load | Refuse to load. No granular grant display. |

SDK shims, plugin-declared rationale, plugin pixels, compatibility scanners, and marketplace review metadata may inform a decision but are never enforcement authorities.

## Secure lifecycle

### Session and supervisor startup

1. The trusted lifecycle/supervisor service starts as `omarchy-plugin-host.service`, a systemd user service wanted by and part of `graphical-session.target`. It is independent of both untrusted workers and the restartable Quickshell process.
2. It opens trusted stores with restrictive ownership and validates their versions before accepting requests.
3. `omarchy-shell` starts and connects only to the trusted surface/control side. It does not scan schema-v2 executable source or evaluate third-party QML.
4. The lifecycle manager enumerates activation records, verifies revision identity and required grants, and asks the supervisor to launch enabled workers.
5. For each worker, the supervisor creates a new generation, cgroup/resource scope, private inherited channel endpoints, and any host-allocated frame resources.
6. The supervisor builds an explicit environment, then enters Bubblewrap with new user, PID, mount, IPC, UTS, and network namespaces; no normal Wayland, D-Bus, agent, credential, or host runtime socket is mounted.
7. The worker receives the activated revision read-only, private scratch/runtime, and only explicitly enumerated FDs. It negotiates protocol versions and reports readiness.
8. The broker and trusted surface host accept messages only after binding their endpoint to the supervisor's plugin/revision/generation record. The first valid surface/frame plus health result completes activation readiness.

### Install

1. Fetch into `U0` staging without hooks or code execution.
2. Validate manifest and complete tree, canonicalize paths, enforce resource bounds, and compute origin/commit/tree/manifest/request fingerprints.
3. Display permission requests in trusted UI. Record explicit selections separately from source.
4. Copy the validated content into the immutable revision store.
5. Create installed-but-disabled state when required grants are absent; otherwise atomically create the activation record and grant binding.
6. Only the supervisor may turn that activation into a worker process.

### Enable and normal operation

1. Reverify revision identity and the current required grants.
2. Launch a fresh worker generation with no ambient authority.
3. Health-check protocol negotiation and, for visual plugins, accept only a valid host-constrained surface/frame.
4. Mark the generation running. Broker checks continue on every call; startup success does not cache authorization.
5. Record bounded lifecycle and decision audit events.

### Update and rollback

1. Fetch and validate a new immutable staging revision while the old revision and worker continue running.
2. Compute and display the code identity change and a separate permission diff.
3. Preserve only identical or narrower grants. Expanded requests remain ungranted until explicit selection.
4. Launch and health-check the candidate in a distinct generation without exposing its surfaces as active authority.
5. Atomically switch activated revision, capability fingerprint, and selected grants, then make candidate surfaces live and terminate the old generation.
6. On any failure, destroy the candidate generation and keep the old activation, grants, handles, and surfaces intact. Rollback is another atomic activation of a retained validated revision, never a Git reset in live source.

### Revoke, disable, crash, and remove

1. Grant revocation is persisted first and becomes visible to broker checks immediately. Affected in-flight operations and handles are cancelled or invalidated.
2. A capability whose safe revocation requires process reconstruction triggers termination and relaunch under the reduced grant. Disablement always stops every worker generation for that plugin.
3. Supervisor teardown closes channels, removes host surfaces, stops the complete cgroup/process tree, invalidates generation-bound handles, and removes scratch/runtime state. Trusted host and other plugins stay alive.
4. A crash follows the same cleanup. Restart is rate-limited and creates a new generation with no stale handles. Crash-loop exhaustion leaves the plugin disabled/unhealthy, not the shell restarted.
5. Removal first completes teardown and detaches activation. It deletes grants and provider-managed integrations transactionally, then retains or deletes private state according to a separate user choice. Audit records follow bounded retention policy.
6. Session shutdown stops accepting new work, revokes interactive/gesture tokens, removes plugin surfaces, terminates workers, drains/cancels broker operations to deadlines, closes trusted stores, and then lets `omarchy-shell` exit.

## Required denial properties

The proposed map is only valid if later implementation proves all of these conditions:

- A worker cannot select, forge, or reuse another plugin's identity, revision, generation, grant, surface id, gesture token, or opaque handle.
- Worker process ancestry, UID namespace, or possession of a broker FD does not itself grant an operation.
- No worker receives the normal session Wayland socket, D-Bus socket, SSH/GPG agent, credential socket, broad host runtime directory, host network namespace, or real home directory.
- Plugin source is read-only and immutable for the generation. Writable state, cache, scratch, revision source, grants, and audit records have distinct ownership.
- All worker-originated protocol data is size-, count-, depth-, rate-, generation-, and type-bounded before trusted allocation or dispatch.
- The trusted host owns every privileged surface invariant and never displays plugin pixels above permission, authentication, lock, or inspection UI.
- Revocation and teardown remove authority before or at the same atomic boundary as visible activation changes; stale channels and handles fail closed.
- A worker crash, render fault, output flood, protocol violation, or resource exhaustion cannot restart or corrupt `omarchy-shell`.
- Schema-v1 plugins remain explicitly `L0`; their unsafe execution cannot consume or be described by schema-v2 granular grants.

## Resolved `G0` seams and later contracts

### Frozen at `G0`

1. **Native artifact ownership:** one C++ `omarchy-plugin-host` daemon contains the supervisor and broker authorities, the QML worker is a private executable, and a public-API native QML bridge module runs inside Quickshell. All ship atomically in Omarchy.
2. **Supervisor lifetime:** `omarchy-plugin-host.service` is wanted by and part of `graphical-session.target`, independent of `omarchy-launch-shell`; detailed restart, recovery, and child-scope behavior belongs to `B0`/`B5`.
3. **Channel bootstrap:** three unnamed inherited `SOCK_SEQPACKET` endpoints use FD 3 control, FD 4 broker RPC, and FD 5 render/input. They share one supervisor launch binding but have separate queues, caps, grammars, and descriptor policies. Direct worker-to-Quickshell communication is forbidden.
4. **Common envelope:** envelope version 1 has a fixed 40-byte header with endpoint role, independently negotiated role protocol, launch generation, and correlation id. Payload caps are 4 KiB, 64 KiB, and 16 KiB for FD 3, 4, and 5. Receivers quarantine delivered descriptors and close them before every error or teardown; trusted-daemon credential checks use the outer PID/UID/GID plus pidfd, while the worker's namespace-translated check is defense in depth and permits legitimate PID zero.
5. **Initial frame transport:** the daemon creates one fixed-capacity memfd containing two writable streaming slots. The host always validates untrusted metadata against trusted allocation state and copies bounded pixels before publication. The sealed immutable one-frame import proves only descriptor, mapping, and copy validation; `B4` owns the live sequence/ownership algorithm.
6. **Test ownership:** deterministic parser, credential, descriptor, sandbox, and frame denials run in native CTest; package/service-manager/compositor boundaries run in the disposable VM; visual changes also require inspected running-UI evidence.

### Can be frozen by Wave 1 contracts

1. Concrete XDG/install paths, permissions, migration from `~/.config/omarchy/plugins`, content-address algorithm, and atomic activation representation.
2. Whether grant, lifecycle, and audit stores share a transactional database or use independently replaceable files with a journal.
3. Broker provider process isolation: in-process modules versus separate narrowly privileged helpers, including failure containment.
4. Bubblewrap runtime image contents, dynamic library/QML import availability, private-state mount versus broker-only access, cgroup mechanism, output capture, and executable/helper policy.
5. Trusted prompt identification and the local CLI authorization model, especially for remote/SSH callers and unattended policy files.
6. Gesture-token creation, lifetime, one-shot semantics, and binding to surfaces and operations.
7. Lock transition behavior, surface inspector ownership, worker behavior while locked, and whether background services may continue granted non-sensitive work.
8. Developer-mode paths, mutable mounts, hot reload, diagnostics, QML inspector exposure, and unmistakable unsafe/managed-runtime labeling.
9. Ordinary-window enablement criteria and exact restricted Wayland globals. Until proven, the socket is absent.
10. Audit retention, redaction, tamper resistance, and user export; private-state retention and backup semantics.
11. Legacy transition policy and whether `unsafe.host-code` is available normally, only by CLI, or only in developer mode.

### Intentionally deferred compatibility seams

- Accessibility, IME, drag and drop, popup/subwindow routing, cursor semantics, non-rectangular input regions, and text selection side channels.
- Restricted GPU render-node access and zero-copy texture sharing. The initial model may deny these while software/shared-memory rendering proves the boundary.
- Multi-plugin service publication and dependencies; these need typed identities and cannot recreate the shared QML object graph.
- The threshold at which a multi-surface package becomes an explicitly trusted host extension rather than a secure plugin.

Deferral means the behavior is reported as unsupported and denied. It does not authorize passing through a host socket, object, path, or generic command to make a fixture work.

## A0 exit assessment

Every proposed trusted component and cross-boundary channel has one named enforcement owner. The six shared `G0` seams are now frozen at the architectural and mock-contract level. Downstream work must still prove the live writable frame protocol, daemon-to-bridge transport and reconnection, service teardown, packaging, compositor behavior, and hostile-system properties without reopening those authority boundaries.
