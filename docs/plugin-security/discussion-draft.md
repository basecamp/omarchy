# Discussion draft: a security boundary for Omarchy plugins

Status: unpublished discussion draft. This is a proposal for review, not a claim that schema v2 is ready for general use or that the competition winner ports have complete live-provider parity.

## The problem is raw code, not metadata

Quattro can make installing an Omarchy plugin feel as lightweight as choosing a theme. The security model cannot adopt that mental model. A plugin revision obtained through Quattro is raw code from outside the trusted Omarchy distribution: QML, JavaScript, images and fonts, parsers, declared helper executables, and any data those programs choose to generate. A manifest describes that code; it does not make the code safe.

Today, loading arbitrary plugin QML into the shell gives it the shell process's imports, objects, filesystem view, environment, compositor connection, credentials reachable by the user, and crash fate. Source review and import filtering can catch mistakes but cannot sandbox one object inside a trusted QML engine. A malicious or compromised plugin can hide behavior behind JavaScript, dynamic object creation, assets, a helper binary, or an update delivered after its initial review.

The relevant attacker controls every byte of a plugin revision and can deliberately crash, loop, allocate, fork, send malformed protocol messages, replay old messages, race an update, and ask for more authority than it needs. The proposal does not attempt to decide whether that code is benevolent. It arranges the system so the code lacks ambient authority and every external effect crosses a smaller, reviewable boundary.

## Principles

The design follows a few rules that should remain true even if the implementation changes:

- Plugin source is data until it is placed in a disposable, confined worker. It is never imported into the trusted shell engine.
- Identity is content-bound. Discovery, review, grants, activation, messages, audit records, update, and revocation refer to an exact plugin id, revision digest, requested-capability fingerprint, launch generation, and authenticated process.
- A request is not authority. A trusted definition installed independently of the plugin gives a capability its meaning, operations, scope grammar, enforcement family, adapter identity, and implementation digest.
- Authorization happens immediately before an effect. The broker rechecks the active revision, exact grant, operation, scope, gesture requirement, adapter binding, correlation state, and revocation epoch on every call.
- Plugins receive operations and opaque handles, not ambient paths, sockets, credentials, executable lookup, compositor objects, or a generic shell.
- The host owns surfaces. Untrusted QML supplies bounded pixels and receives bounded input; it does not choose z-order, exclusive zones, monitor policy, lock-screen visibility, global focus, or compositor protocols.
- Failure is ordinary. A denied permission, malformed packet, provider timeout, worker crash, stale update, or exhausted budget fails closed and tears down authority associated with that generation.
- Compatibility is explicit. Legacy trusted plugins continue through a separately named path while secure plugins migrate; schema numbers must not imply that old code silently acquired confinement.

These rules matter more than whether the permanent supervisor and broker are written in C++, Rust, or another systems language.

## Preserve arbitrary QML without trusting it

The proposal deliberately does not replace plugins with a fixed card or widget schema. A plugin may keep ordinary Qt Quick composition, custom components, JavaScript models, animations, transparency, irregular hit areas, sprites, drawers, overlays, pets, and other visual work that made the competition interesting.

That QML runs in a separate Qt worker inside Bubblewrap. The worker gets a read-only bind of one verified revision, a synthetic home, private temporary and runtime directories, filtered environment, no Linux capabilities, no host D-Bus or ordinary Wayland socket, and separate authenticated control, broker, and render channels. A systemd user scope supplies memory, CPU, task, runtime, output, and restart limits. The trusted host allocates the surface, copies validated frames from shared memory, clips input, and composes the result into shell-owned UI.

The boundary changes surface construction, not the plugin's visual language. A bar widget becomes arbitrary remote QML in a host-assigned bar envelope. A panel, overlay, or desktop pet becomes arbitrary remote QML in a bounded host-owned surface. Placement and privileged compositor behavior remain host policy. Raw pixels also do not provide accessibility semantics, so a production design needs a bounded, validated accessibility side channel rather than pretending image transport solves accessibility.

Software rendering is the current compatibility profile. It is useful because it avoids giving hostile workers a graphics-device and compositor attack surface, but it is not free: complex shaders, particles, GPU effects, high frame rates, and large animated surfaces may need adaptation or a separately designed restricted GPU profile. The measured render proofs establish feasibility for representative fixtures, not universal performance.

## Sidecars are allowed, but they do not inherit authority

Some plugins contain a parser, model daemon, or computational helper that is awkward to express in QML. A manifest may declare sidecar executables packaged inside the same revision. They run in the same Bubblewrap, cgroup, mount, PID, IPC, UTS, and network isolation as the QML worker. QML and a sidecar may share private files or local sockets inside that sandbox.

A sidecar does not receive the worker's control, broker, or render descriptors. Sharing the sandbox also does not confer network, D-Bus, Wayland, Bluetooth, PipeWire, Docker, credential, or host-filesystem authority. If a helper needs one of those powers, it is not an untrusted sidecar; it is a provider candidate and requires separate packaging, review, confinement, identity, and lifecycle.

This distinction is important for the winner migrations. Radio Atlas's fetch proxy and media controller, AirPods' Bluetooth and audio daemon, and GitHub's credential-bearing `gh` calls do not become safe by moving beside QML. Their reusable policy belongs in trusted or separately sandboxed providers. Pure parsing, state machines, and bounded computation can remain plugin-owned.

## Brokered capabilities

The worker sees a small QML API. It can inspect availability for capabilities its exact manifest requested and invoke a named operation with a bounded structured payload. Calls have host-created correlation identities and one terminal completion. Permission snapshots and call completion arrive through stable runtime signals so a fast provider response cannot race a QML `Connections` retarget.

Availability is a host-derived UX snapshot, not an authorization token. It exposes only the requested capability and operation names plus their current granted state; it does not expose the grant store, scopes for other plugins, provider internals, or undeclared capabilities. Optional permissions let QML hide, disable, or replace unavailable features, while the broker remains authoritative on every invocation and sends a reduced snapshot after revocation.

The broker owns effects. Compiled capability families cover common operations such as quota-bound private storage, packaged audio cues, and desktop notifications. Extensible capabilities use independently installed definition documents. A dynamic request pins the canonical definition name, generation, digest, requested operation subset, and canonical scope; QML cannot substitute those fields. Activation additionally binds a reviewed adapter class, ABI, and implementation digest. Unknown, stale, ambiguous, unavailable, or scope-invalid definitions cannot be granted.

### Who defines permissions, and how extension works

A plugin may request a permission name, but it cannot create a permission or give that name meaning. Authority exists only when the host already has an independently trusted capability definition and provider adapter matching the exact name, generation, definition digest, operations, scope grammar, ABI, and implementation digest. An unknown name is an unavailable request, not a new namespace that the plugin controls. Two plugins requesting `service.gh` and `cli.gh` therefore do not receive two independently meaningful ways to run `gh`; both names remain inert unless trusted definitions were separately installed for them.

Omarchy should ship a small built-in registry for common stable effects. Each built-in definition maps a human-facing permission to a closed operation set and enforcement policy. For example, private storage maps `read` and `write` to one plugin-owned quota; notifications map `send` to reviewed categories; packaged audio maps `play-cue` to immutable files in the verified revision. These are not string labels around a generic executor. The mapping is the permission.

Users and system integrators may extend the registry, but extension is a trusted administrative action separate from plugin installation. A custom definition such as `bash.my-harness` can name one resolved executable, enumerate allowed subcommands, define a typed argument grammar, cap input/output/runtime, select whether a fresh gesture is required, and bind a separately reviewed adapter implementation. It must not degrade to shell text, arbitrary argv, ambient `PATH` lookup, or a plugin-selected executable. Definitions need collision-resistant ownership or namespaces, explicit versions and generations, content digests, upgrade and removal rules, and a command that shows which installed plugins currently depend on them.

A plugin package may include a proposed definition as documentation or an installation suggestion, but that proposal is inert. Installing or updating the plugin must not install the definition, provider, package dependency, system service, or grant. The user must obtain and review the trusted definition/provider through a distinct Omarchy or system-administration path. This prevents a plugin from shipping both the request and the code that decides what the request authorizes.

The manifest is also the ceiling for runtime behavior. QML can inspect only the requested optional and required permissions, adapt its UI to the current snapshot, and invoke only operations in the reviewed subset. It cannot discover unrelated definitions, add a request at runtime, widen scope, change adapters, or mint handles. A new request or broader scope requires a new immutable plugin revision and permission review. A definition or provider upgrade with a new digest or generation similarly invalidates the old binding until it is reviewed.

Runtime grant changes are reductions or explicit reviewed transitions, never plugin decisions. Granting an optional permission makes its declared operations available; revocation increments its epoch, cancels or invalidates outstanding work and opaque handles, updates the broker before the QML availability snapshot, and may hide or disable the associated feature. Revoking a required permission disables that exact activation unless the manifest defines a safe degraded profile. A plugin may ask the host to open the permission UI for one of its declared requests, but it cannot approve the prompt or distinguish policy denial from unavailable provider details beyond the bounded status needed for honest UX.

The review UI should make this chain visible rather than presenting a bag of arbitrary strings:

```text
plugin manifest request
  → trusted definition (name + generation + digest)
    → requested operation subset + canonical scope
      → user grant (state + epoch)
        → reviewed adapter (class + ABI + implementation digest)
          → broker recheck immediately before each effect
```

This separation is what makes permission extensibility compatible with confinement: names remain ergonomic, while independently installed definitions, grants, adapters, and per-call broker checks supply their enforceable meaning.

A concrete permission matrix makes the ownership boundary easier to review:

| Case | What the plugin may declare | What gives the request meaning | Result |
| --- | --- | --- | --- |
| Built-in `storage.private` | Operations and a quota within the built-in schema | Omarchy's compiled definition and private-storage provider | The user may grant a narrower quota; every read/write/remove is broker-checked |
| Administrator extension `bash.my-harness` | An exact definition generation and digest, selected operations such as `status`, and the named profile scope | A separately installed trusted definition plus a reviewed adapter for one digest-pinned executable and closed argument grammar | The request remains unavailable until the administrator installs that integration; it never means arbitrary Bash or argv |
| Unknown `plugin.whatever` | The inert request and publisher rationale | Nothing | It cannot be granted or invoked, even if the plugin bundles a `.capability` proposal |
| Plugin update adds `drive` or widens the profile | A new immutable manifest revision | A new explicit permission review | The old grant cannot authorize the added operation or expanded scope |
| Optional grant is revoked | The plugin may observe that its declared feature is unavailable | The broker changes the grant epoch before publishing a reduced availability snapshot | QML can hide or disable the feature; pending and subsequent effects are denied |
| Required grant is revoked | Nothing beyond the already declared request | Host lifecycle policy | The activation is disabled or fails closed; QML cannot keep using the old epoch |

The reference test uses `bash.my-harness` only as a deliberately provocative naming example. Its adapter is fake and bounded. The contract rejects shell executables, shell strings, arbitrary argv, executable replacement, undeclared subcommands, malformed arguments, unbounded output, and overlong execution. A safer production name would describe the actual integration rather than its implementation, but the authority comes from this binding—not from how reassuring the name sounds.

This is extensibility without a generic escape hatch. A future GitHub account reader can define bounded datasets and opaque account handles. A device controller can enumerate supported controls and require a fresh gesture for mutations. A network provider can constrain scheme, host, method, redirects, body size, response size, and rate. A command adapter, when unavoidable, names one installed executable and enumerated operations with validated arguments; it never accepts shell text or arbitrary argv.

Providers should receive a broker-created authorization context containing the immutable activation binding, canonical capability reference, grant epoch, operation, and validated demand. They must derive account, device, and resource selection from that context and opaque handles rather than plugin-supplied paths or credential identifiers. High-risk providers should be separate processes so a network parser or hardware stack is not folded into the main host's trusted computing base.

The current live-lab composition implements only quota-bound plugin-private storage, desktop notification through Omarchy's fixed notification helper, and packaged audio through `pw-play`; it is explicitly gated, manually launched, and not a production provider service. Dynamic GitHub, Radio Browser, Bluetooth, general network, CLI-harness, URI, device, and media definitions are contracts, fixtures, or fake-adapter proofs unless a section above says otherwise. Schema v2 remains disabled for ordinary users, and the ordinary preview uses a deny-all broker.

## Identity, grants, updates, and audit

The secure lifecycle starts by parsing a bounded schema-v2 manifest, hashing the complete revision tree, and storing content in an Omarchy-owned revision area that rejects links and unsafe paths. Preparation pins the verified directory rather than reopening an attacker-controlled pathname at launch. The launcher creates one tuple of control, broker, and render endpoints bound to the plugin, revision, role, generation, expected UID, and pidfd-backed process identity. Endpoint credentials, generation, message schema, correlation, payload size, and descriptor count are checked before dispatch.

Grants live outside plugin source and outside shell configuration. They bind the canonical plugin and revision request to a trusted capability definition, adapter, operation subset, canonical resource scope, persistence or gesture mode, and revocation epoch. A plugin can render a denied or unavailable state but cannot edit the store. Audit records describe authorization outcomes and bounded metadata; provider payloads, tokens, notification bodies, device identifiers, and returned secrets must not be logged.

An update is a new identity, not an in-place continuation. The lifecycle stages and validates a candidate, computes whether its requests expand authority, carries forward only compatible grants, health-checks the candidate, and supports rollback without allowing stale generations to reuse channels or handles. Revocation changes the epoch checked by the broker. In-flight asynchronous and streaming providers still need explicit cancellation proofs before live dynamic providers can be considered complete.

Installation follows the same separation. The installed host, private worker, permission and audit tools, QML bridge, service unit, dependencies, modes, ownership, ELF properties, and exact file set are package-verified. Test workers, fake providers, fixtures, proof programs, malicious peers, and migration tools are not installed. Schema-v2 discovery and activation remain feature-gated and use roots separate from the legacy plugin path during rollout.

## Migration and compatibility

There is no honest manifest-only conversion for an existing plugin. Its QML must move out of the trusted shell engine, and every ambient effect must become a broker operation. Much of the code can still survive:

- Qt Quick layout, drawing, animation, local components, reducers, parsers, sorting, validation, and state machines usually move unchanged.
- `Process`, detached commands, direct HTTP, notifications, clipboard access, URL opening, and compositor commands become typed asynchronous broker calls.
- `FileView` private state becomes quota-bound private storage; user files require revocable opaque handles selected through trusted UI.
- Shell singleton and service access becomes explicit versioned settings, state, events, and named actions.
- Direct layer-shell windows become named host-managed surface envelopes.
- Plugin IPC handlers become plugin-scoped named commands rather than ambient shell endpoints.

Omarchy should ship a compatibility bootstrap and migration tooling that identifies imports and ambient APIs, generates a review checklist, and offers familiar asynchronous wrappers. The tool can make mechanical changes, but authors must still choose meaningful scopes, denial behavior, surface policy, and which integrations deserve trusted providers.

Legacy schema-v1 plugins should remain an explicitly unsafe, trusted-extension mode during migration. They should be clearly labeled, disabled from automatic equivalence with schema v2, and never receive a badge implying confinement. A staged rollout can begin with opt-in schema-v2 installation, a permission CLI and Setup surface, a small provider set, and side-by-side winner previews. Default enablement comes only after installed-binary VM evidence and a compatibility policy for the QML API, private protocols, grants, and audit formats.

## What the winner ports establish

The Radio Atlas, Omagotchi, AirPods, and GitHub dashboard ports show that arbitrary custom QML can survive the boundary and that ambient mechanisms can be mapped to narrow capabilities. Their manifests parse, QML lints, external fixtures load trusted definitions independently, fake adapters exercise exact operation binding, and representative scenes render through the software shared-memory path. Omagotchi demonstrates compiled private storage, packaged audio, and notification requests. The other three demonstrate dynamic definition and adapter identity.

They are not evidence of live parity. Radio Atlas still needs reviewed HTTPS and media providers, DNS and redirect policy, opaque stream handles, and network/audio tests. AirPods needs separately packaged Bluetooth and audio integration plus real hardware. GitHub needs credential custody, pagination and rate policy, a test account, and live read/write/open operations. Multi-surface composition, provider response decoding, cancellation, and complete asynchronous UI handling also remain incomplete. A fake adapter proves the authorization seam, not the external service.

## Rollout and evidence bar

The current reusable security campaign contains 25 deterministic tests. It covers bounded manifest, wire, permission, render and sandbox contracts; real Bubblewrap and endpoint credentials; sidecar descriptor isolation; broker authorization; revision, grant and audit stores; malicious peers; descriptor injection; stale generations; rendering and input; and exhaustion cases. The product E2E additionally launches a non-installed test host and worker through the real main/product stack, observes broker calls and QML completion, and exercises startup permission state followed by revocation. The revoke scenario passed 20 consecutive prompt-mutation runs after frame pacing and retry were made robust against host admission drops.

The live desktop campaign produced exact-window PNGs, compositor state, process trees, private-state bytes, grant mutations, and correlated audit records. It did not produce an MP4: the available recorder path could not capture this Wayland session reliably, so the evidence must not imply video exists. Pointer delivery was proven through authenticated protocol and Qt delivery tests, and host routing was exercised, but the automation environment did not provide a trustworthy physical-pointer actuator for a complete human-device-to-plugin trace. Those are evidence gaps to close in a disposable VM or acceptance setup, not reasons to weaken the input boundary.

That campaign is necessary but not sufficient. It is deterministic regression evidence, not sustained fuzzing or a formal proof. Before default enablement, the exact installed Release binaries should pass in a disposable VM with sanitizer and coverage-guided parser campaigns, long-running CPU/memory/task/frame abuse, concurrent hostile plugins, network and session-bus escape canaries, crash and rollback injection, provider timeouts, audit failure, and real revocation of queued and streaming work. The live winner integrations require real services, accounts, devices, and user-visible denial behavior. The accessibility channel, restricted GPU option, same-user store mutation hardening, audit confidentiality and rate limiting, provider process isolation, and public compatibility commitments remain open design work.

## Why any native code is justified, and how much is acceptable

The proposed boundary needs operations Bash and QML cannot safely provide: credential-bearing `SOCK_SEQPACKET` channels, exact descriptor inheritance and quarantine, pidfds, seccomp filters, namespaces, cgroup supervision, bounded binary codecs, shared-memory frame publication, and a Qt Quick renderer outside the trusted shell. Shell remains appropriate for packaging and orchestration around this boundary; it is not an appropriate parser or asynchronous authority broker for hostile binary traffic.

The cost is substantial. Measurements from the clean pre-rebase candidate corresponding to current commit `36d35394` count 25,624 C/C++ lines when conventional test paths and test names are excluded and 43,497 C/C++ lines in the complete reference tree. That candidate's clean Release bundle installed `/usr` tree is 2,848,726 bytes. Its host is 1,324,296 bytes, private worker 596,824 bytes, permission CLI 456,432 bytes, and audit CLI 330,624 bytes. A full `BUILD_TESTING=ON`, two-job Release build on the development machine completed in roughly 67 seconds; that is a local observation, not a CI target. The live-tested bundle digest is `36b06e268e6d8bd51c8f64cfff34ca52a08790bb0cb6c3b710e3034a9f94000c`. After rebasing onto current `upstream/quattro`, the rebuilt tree again passed the 25-test security campaign and 20 product E2E repetitions, but that rebuilt binary was not substituted into the recorded desktop campaign.

The installed runtime depends on Qt 6 Core, Gui, QML and Quick, Bubblewrap, libseccomp, systemd integration, the C++ runtime, libc, and the kernel's namespaces, seccomp, pidfd and Unix-socket behavior. The host-side trusted computing base includes manifest and protocol parsers, launcher and authenticated channels, grant/revision/audit lifecycle, broker authorization, providers, frame consumer, surface policy, bridge, and product composition. The worker and plugin sidecars are hostile workloads rather than authority-bearing components, but their Qt and parser attack surface still affects sandbox escape risk and availability. Provider code is the most sensitive extensibility point because it holds credentials or performs effects.

The reference tree is therefore a proof vehicle, not a blank check to merge 43,000 lines as one permanent subsystem. Production review should separate installed targets from fixtures and proofs, hide accidental ELF symbols, freeze the small QML API, keep private protocols exactly versioned, publish reproducible LOC/build/size/dependency metrics in CI, and assign owners for the launcher, broker, render boundary, storage formats, and provider registry.

Alternatives remain worth pursuing. Portals should replace custom capability code for files, URIs, capture, and devices wherever their semantics fit. A Rust supervisor and broker with a narrow C++ Qt bridge and disposable Qt worker could move attacker-controlled parsing and lifecycle state into a memory-safe implementation while retaining arbitrary QML. Separately sandboxed provider services can keep credential and network parsers out of the host. Bash and systemd can continue to install, start, monitor, and package those native pieces. The existing trusted in-process plugin path can remain only as an explicitly unsafe mode.

The native-code justification is not speed. It is that preserving arbitrary QML while removing ambient user authority requires a real process, protocol, authorization, and rendering boundary. If a smaller implementation can enforce the same identity, descriptor, revocation, resource, and surface properties, it should replace this reference. If it cannot, reducing line count by moving checks back into conventions would be a security regression rather than simplification.
