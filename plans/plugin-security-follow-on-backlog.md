# Secure plugin follow-on backlog

> Issue-ready planning artifact only. No external issues have been created. Revalidate dependency states and G4 evidence before copying an item into GitHub.

## Purpose and ordering

This backlog separates work that blocks any supported schema-v2 activation from work that can follow a deliberately small version-1 release. The dependency names refer to the completed nodes and evidence in [`plugin-security-work-graph.md`](plugin-security-work-graph.md). A follow-on may depend on another item in this document; those dependencies are named explicitly so issues can be created without losing ordering.

An activation blocker must close before `PluginHostInfo.available` becomes true or an end-user command starts a secure worker. A post-v1 enhancement must remain denied or unavailable until its own acceptance criteria pass; it does not justify delaying a useful initial release whose manifest and compatibility documentation report the unsupported behavior honestly.

## Activation blockers

### Z2-A1: Compose the production plugin host

Suggested issue title: `Compose the secure plugin lifecycle, broker, and surface runtime in omarchy-plugin-host`

- Class: activation blocker
- Depends on: C0–C8, D0–D5, E0–E4, F0–F4; final aggregate-registration result from G4
- Scope: replace the inert `host/main.cpp` event loop with one trusted owner for discovery, immutable revision selection, grant state, launcher/supervisor, authenticated channels, broker runtime/providers, render sessions, trusted bridge sessions, surface admission, health, teardown, and authoritative audit. Keep configuration and executable selection trusted; do not introduce shell command composition or plugin-selected Bubblewrap arguments.
- Acceptance criteria:
  - Starting the user service with the feature gate disabled remains inert and reports unavailable.
  - With the gate enabled, one exact activated schema-v2 revision launches only after manifest, revision, grant, policy, generation, and health identities agree.
  - The production path uses the C7 launcher and D1 authenticated channels rather than an in-process test shortcut.
  - A Pomodoro bar surface, pet overlay, and fake-service request traverse the installed production host without expanding the closed provider set.
  - Disable, revoke, remove, crash, service restart, and Quickshell restart clear or recover exact resources without resurrecting stale authority.
  - Aggregate Debug, Release, ASan/UBSan, real-Bubblewrap, and hostile tests pass; `PluginHostInfo.available` changes only in the final reviewed activation commit.

### Z2-A2: Wire schema-v2 product lifecycle and trusted permission review

Suggested issue title: `Wire secure schema-v2 install, enable, update, rollback, revoke, and remove commands`

- Class: activation blocker
- Depends on: Z2-A1, D0, E4, E5, F3, F4; command-metadata and install-script guides before editing product commands
- Scope: connect current product command names to the D0 lifecycle for schema v2, retain the explicit schema-v1 unsafe path, surface candidate health and permission diffs, and invoke a trusted review surface. Do not let `--yes`, noninteractive stdin, manifest prose, or plugin pixels choose grants.
- Acceptance criteria:
  - Install and update stage immutable content without loading candidate QML into the current shell.
  - Required and optional permission decisions bind to the full candidate revision, policy fingerprint, source fingerprint, and generation.
  - Noninteractive operation cannot add or expand authority; unchanged-policy automation requires an explicit user policy.
  - Candidate denial or failed health leaves the prior healthy revision active; promotion ambiguity rolls back with a fresh generation.
  - Disable/revoke/remove immediately deny new effects, cancel/restart according to the capability contract, and make stale handles unusable.
  - CLI help, metadata, migration, rollback, interruption, and recovery tests pass without altering the schema-v1 honesty contract.

### Z2-A3: Land package ownership and reproducible clean-source artifacts

Suggested issue title: `Package the native plugin runtime from a clean pinned Omarchy revision`

- Class: activation blocker
- Depends on: Z2-A1 and the final aggregate CMake/install layout; sibling `omarchy-pkgs` ownership decision
- Scope: land the reviewed package recipe or select an equivalent package boundary, build without `--nocheck` from an exact clean source commit, and keep the private worker outside `PATH`. Higher-risk providers may be split into separate packages/services when that improves isolation, but package boundaries must not create version-skewed protocol modules.
- Acceptance criteria:
  - The committed recipe identifies the exact Omarchy source revision and produces a reproducible archive from a clean checkout.
  - Package checks run the complete intended Release aggregate rather than only the skeleton targets.
  - The archive contains one ABI-compatible `Omarchy.PluginHost` module, the trusted host, private worker, permission/audit CLIs, systemd user unit, and required metadata with correct modes and no duplicate URI.
  - The worker is absent from `/usr/bin`, rejects direct execution, and the host/module have no unexpected RPATH/RUNPATH or undeclared runtime dependency.
  - The package verifier and an extracted-tree dynamic import pass against the exact archive digest recorded in evidence.

### Z2-A4: Close the disposable-VM and fresh-ISO release gate

Suggested issue title: `Prove secure plugin installation and activation in a fresh Omarchy VM`

- Class: activation blocker
- Depends on: Z2-A2, Z2-A3, available `omarchy-iso` checkout and acceptance harness
- Scope: build a fresh ISO using the committed Omarchy and package sources, install without reusing a base image, and exercise the actual graphical session, systemd user service, Quickshell module, worker sandbox, permission review, surfaces, broker effects, update/revocation, and recovery. Do not run destructive graphical acceptance in the active development session.
- Acceptance criteria:
  - Logs record the exact ISO, package archive digest, Omarchy commit, package commit, kernel, Qt, Bubblewrap, systemd, compositor, and GPU/software-render profile.
  - The graphical-session service enables and starts correctly, Quickshell imports the installed module, and the production host—not a generic Qt probe—owns the plugin surface.
  - The installed Pomodoro, pet, and fake-service examples pass their positive flows and the expected denial flows.
  - VM evidence covers actual network namespace, home/bus/Wayland/agent denial, cgroup limits, crash/daemon/shell restart recovery, permission-expanding update, revocation, and direct-worker rejection.
  - Screenshots and logs clearly identify trusted versus plugin pixels and show no permission prompt inside plugin-controlled content.
  - The run closes the live compositor, fractional-DPR, monitor change, presentation latency, and clean-install gaps or records an explicit release blocker.

### Z2-A5: Freeze the schema-v1 transition and developer-mode policy

Suggested issue title: `Adopt an explicit unsafe.host-code transition policy for schema-v1 plugins`

- Class: activation blocker for changing defaults; policy may be discussed before Z2-A1
- Depends on: discussion decision, E5, F4, F6, SDK plan Z2-A6
- Scope: decide how already-enabled legacy plugins transition, where the unsafe grant is available, whether new unsafe installs remain supported, and how managed plugins differ from explicit developer/host extensions. Preserve power-user freedom without representing in-process QML as granularly sandboxed.
- Acceptance criteria:
  - List, install, enable, update, and menu surfaces use one unambiguous `unsafe.host-code` posture for schema v1.
  - `--yes` never grants unsafe host access, and no schema-v1 request enters the granular grant store or sandbox eligibility path.
  - Existing enabled plugins follow the chosen notice/confirmation/disable schedule with a tested rollback and recovery story.
  - Managed legacy updates are staged and immutable; arbitrary hot reload is limited to explicit developer paths.
  - Documentation explains that host extensions can read files, run commands, access session services, spoof shell UI, and crash the shell.

### Z2-A6: Ship the minimal schema-v2 author SDK and conformance kit

Suggested issue title: `Ship the secure plugin SDK, compatibility helpers, and conformance fixtures`

- Class: activation blocker for ecosystem-facing release
- Depends on: frozen v1 manifest, wire, surface, and provider contracts; E1–E3; F6
- Scope: provide stable QML-facing typed clients for the initial providers, lifecycle/theme/input state, local development, migration examples, and deterministic host fakes. Helpers remain clients of policy and never become an alternate authority path.
- Acceptance criteria:
  - Authors can build and test a bar widget, transparent overlay, and authenticated-service UI without importing trusted Omarchy objects.
  - The SDK reports unsupported imports, operations, surface roles, and software-render features before submission where practical.
  - Named operations serialize only closed schemas and cannot supply plugin identity, host paths, arbitrary file descriptors, provider names, audit actors, or Bubblewrap arguments.
  - A sandboxed mutable-source developer mode and an explicitly unsafe host-extension mode have distinct commands, diagnostics, and visual identity.
  - Fixtures and conformance tests pin API/protocol versions, bounds, denial behavior, teardown, and forward-compatibility rules.

## Post-v1 capability and portal issues

### Z2-P1: User-owned file handles and private-storage export

Suggested issue title: `Add trusted open/save portals with revocable opaque file handles`

- Class: post-v1 capability
- Depends on: Z2-A1, B2/C4 provider contract, F4 trusted UX; informed by MyJournal, AI Panel, TOTP, Omashot, and Textify migrations
- Scope: separate plugin-private storage from user-owned documents; add user-selected open/save handles without exposing host paths or broad directory mounts.
- Acceptance criteria:
  - Handles bind to exact plugin/revision/generation/grant epoch, access mode, selected object, and lifetime.
  - Save uses a trusted destination and atomic replace policy; open cannot traverse outside the selected object.
  - Revocation, rename/replacement races, symlinks, special files, oversized data, stale handles, and provider restart fail closed.
  - The permission surface explains persistence and whether another application can edit the same data.

### Z2-P2: Credential, clipboard, selection, and focused-input portals

Suggested issue title: `Add opaque credential and gesture-bound clipboard/input portals`

- Class: post-v1 high-risk portal family
- Depends on: Z2-A1, trusted prompt/gesture identity, composed-risk UX; informed by 1Password, TOTP, AI Grammar, and AI Panel
- Scope: keep credentials opaque where possible, separate clipboard read/write, require fresh trusted gestures for sensitive reads and input insertion, and prevent hidden-focus or wrong-target actions.
- Acceptance criteria:
  - Credential list returns non-secret descriptors/opaque handles; copy/submit operations can complete without returning secret bytes to QML.
  - Selection/clipboard read plus any output channel triggers an elevated composed-risk decision.
  - Focused input shows a trusted target preview/confirmation and aborts on focus change.
  - Single-use gesture tokens, cancellation, revocation, expiry, audit redaction, lock-screen denial, and cross-plugin replay tests pass.

### Z2-P3: Scoped HTTP and authenticated service adapters

Suggested issue title: `Add scoped HTTP and first real authenticated-service provider`

- Class: post-v1 capability
- Depends on: Z2-A1, C8 bounds/cancellation, F4 permission UX; choose a Basecamp-style provider as the first migration candidate
- Scope: broker HTTPS and explicit loopback requests by scheme, host, port, method, redirect, body/result, concurrency, and rate; retain credentials in a trusted provider; prefer enumerated domain operations over generic request access.
- Acceptance criteria:
  - The worker has no raw network namespace access and cannot choose an undeclared host, method, redirect target, socket type, or provider credential.
  - DNS rebinding, redirect crossing, loopback/private-range ambiguity, Unix sockets, oversized/streaming responses, cancellation, timeout, and credential leakage have adversarial tests.
  - The real provider exposes enumerated operations and redacted audit records; no generic CLI fallback exists.
  - Permission review explains composed risks with files, clipboard, capture, and credentials.

### Z2-P4: Capture, OCR, and opaque media handles

Suggested issue title: `Add a trusted screen-capture portal and bounded media-handle pipeline`

- Class: post-v1 high-risk portal family
- Depends on: Z2-A4 live compositor evidence, trusted overlay identity, B4/D2 frame bounds; informed by Omashot, Overview, TOTP, and Textify
- Scope: keep authoritative monitor/window/region selection and confirmation in trusted UI, return opaque captured-media handles, and allow bounded local compute such as OCR without exposing screencopy or compositor authority.
- Acceptance criteria:
  - Plugin pixels cannot cover or imitate the authoritative capture selection/confirmation chrome.
  - Handles constrain media type, dimensions, byte size, lifetime, consumer operation, and export/clipboard rights.
  - Capture plus network or credentials receives elevated composed-risk review.
  - Lock-screen, protected-surface, stale monitor/window, cancellation, repeated capture, recording duration, storage, and revocation cases pass in the VM.

### Z2-P5: Media, devices, local services, and system-state adapters

Suggested issue title: `Design bounded media, Bluetooth/device, proxy, Docker, update, and compositor adapters`

- Class: post-v1 provider program; split into separate issues before implementation
- Depends on: Z2-A1 and a per-provider threat model; F6 mappings for Omapods, Docker Monitor, Mihomo, Overview, Peek, Spotify, DPMS Guard, and System Updates
- Scope: define separate observe/control/destructive capabilities, resource scopes, trusted gestures, rollback, package/service ownership, bus/device policies, and process isolation. Never mount Docker, system D-Bus, compositor control, package-manager, or unrestricted service sockets into the worker.
- Acceptance criteria:
  - Each provider has a closed operation schema, independent package/process decision, scope model, cancellation/revocation mode, audit vocabulary, limits, and adversarial suite.
  - Read-only observation cannot imply mutation; destructive actions require fresh trusted confirmation where appropriate.
  - Docker control is treated as host-root-equivalent authority; update operations invoke only Omarchy-owned workflows; compositor rules use closed templates and predicates.
  - Provider installation/update/removal is transactional and cannot be initiated by an untrusted plugin lifecycle hook.

### Z2-P6: URL activation, open-URI, application launch, and default handlers

Suggested issue title: `Add trusted URL activation and constrained application-launch portals`

- Class: post-v1 portal family
- Depends on: Z2-A1, trusted gesture tokens, F4 spoof/composed-risk UX; informed by Browser Picker and Basecamp
- Scope: distinguish receiving an opaque URL activation, opening a scoped URI, enumerating browser profiles, launching a selected application/profile, and changing the system default handler.
- Acceptance criteria:
  - Schemes, hosts, profiles, applications, and argument shapes are host-validated and cannot become arbitrary process execution.
  - Default-handler changes require high-visibility trusted consent and reliable rollback/removal cleanup.
  - Login/payment callback interception, malformed URI, command-line injection, stale gesture, hidden focus, and cross-plugin activation tests pass.

## Post-v1 UI and rendering issues

### Z2-U1: Accessibility semantics side channel

Suggested issue title: `Design a bounded accessible semantics protocol for remote plugin QML`

- Class: post-v1 compatibility
- Depends on: stable surface/input protocol, trusted bridge, accessibility review
- Scope: convey a bounded semantic tree, roles, labels, states, focus, actions, and incremental updates without exposing trusted shell objects or accepting unbounded plugin strings/trees.
- Acceptance criteria:
  - Screen readers can navigate and activate the representative bar, panel, and overlay where the surface role permits interaction.
  - Node count, depth, text, update rate, action set, focus ownership, stale-node behavior, and teardown are bounded and fuzzed.
  - Trusted prompts and authentication surfaces remain in a separate accessibility namespace and cannot be imitated through metadata.

### Z2-U2: IME, text selection, drag and drop, popups, tooltips, and cursors

Suggested issue title: `Add secure remote-view interaction side channels beyond pointer and key input`

- Class: post-v1 compatibility program; split by protocol once designed
- Depends on: stable surface/input protocol, trusted focus/gesture authority, Z2-U1 where semantics overlap
- Scope: specify host-mediated IME preedit/commit, selection ownership, drag offers, drop handles, popup/tooltip geometry, cursor names/images, and cancellation. Plugin QML never creates an independent privileged native surface or receives arbitrary host paths.
- Acceptance criteria:
  - Each side channel has exact roles, bounds, sequence/lifetime rules, identity binding, cancellation, and stale-generation behavior.
  - Popup/tooltip surfaces cannot escape the parent envelope, obscure trusted prompts, acquire ungranted keyboard focus, or bypass surface count/rate limits.
  - Drag/drop data uses typed bounded offers or opaque handles; IME and selection content are delivered only to the correctly focused generation.
  - Representative rich editor, list reordering, tooltip, menu, and cursor fixtures pass graphical VM tests.

### Z2-U3: Additional surface roles and ordinary windows

Suggested issue title: `Expand secure plugin surface roles beyond bar and desktop overlay`

- Class: post-v1 compatibility
- Depends on: Z2-A4 compositor evidence, D3/E2 policy model
- Scope: review `popover`, `slideout`, `desktop-underlay`, `ordinary-window`, and `bar-replacement` individually; define fixed monitor, anchor, exclusive-zone, focus, full-screen, lock, count, size, and pacing invariants.
- Acceptance criteria:
  - Every role has a host-owned placement and inspection policy and cannot select trusted layer namespaces.
  - Ordinary windows receive only a compositor security-context connection with an audited protocol allowlist, never the normal session Wayland socket.
  - Multi-monitor, hotplug, fractional DPR, workspace, lock, focus-stealing, full-screen spoof, and teardown tests pass in the VM.
  - The review defines when many surfaces or a full bar become a trusted shell-extension class.

### Z2-R1: Restricted GPU rendering profile

Suggested issue title: `Prototype and threat-model a restricted GPU profile for plugin QML`

- Class: post-v1 rendering compatibility
- Depends on: stable copied software path, Z2-A4 measurements, kernel/driver isolation review
- Scope: restore ShaderEffect, particles, and GPU-dependent Qt Quick behavior without sharing trusted graphics authority or weakening process/resource isolation.
- Acceptance criteria:
  - The proposal identifies device nodes, driver ioctls, graphics APIs, shader/compiler inputs, memory accounting, synchronization, reset/hang behavior, and cross-context leakage risks.
  - Malformed shaders, allocation storms, GPU hangs/resets, worker crashes, device loss, and compositor restart leave the shell recoverable.
  - Fidelity and performance comparisons use the same representative scenes and physical outputs as the software profile.
  - The software profile remains available and manifests declare/report profile requirements honestly.

### Z2-R2: Zero-copy or shared-texture frame transport

Suggested issue title: `Evaluate zero-copy plugin frame transport without trusting worker-owned memory`

- Class: post-v1 performance enhancement
- Depends on: Z2-R1 for GPU textures or a separately reviewed CPU transport; B4/D2 coherence contract and F2 metrics
- Scope: measure whether copying is a real bottleneck before changing the security boundary; define ownership, immutable publication, synchronization, descriptor provenance, format/modifier negotiation, lifetime, and fallback.
- Acceptance criteria:
  - Benchmarks show a material end-to-end improvement under realistic compositor presentation rather than only microbenchmarks.
  - The host never samples mutable worker data as trusted state, and descriptor/format/stride/offset/size validation is overflow-safe.
  - Reuse, stale slot, concurrent mutation, fence abuse, descriptor substitution, device loss, and producer exit preserve the last valid frame or fail closed.
  - A copied bounded fallback remains available for unsupported hardware and recovery.

## Ecosystem, supply chain, and migration issues

### Z2-E1: Marketplace publisher identity, signing, attestations, and revocations

Suggested issue title: `Design signed marketplace identity and revision attestations for plugins`

- Class: post-v1 supply-chain enhancement
- Depends on: immutable local origin/content identity and package ownership; marketplace governance decision
- Scope: define publisher-to-plugin identity, source/revision/artifact attestations, key rotation/recovery, review status, revocation, transparency, and offline behavior. Treat attestations as evidence in addition to—not a replacement for—the runtime sandbox and local digest checks.
- Acceptance criteria:
  - The threat model covers compromised publisher, marketplace, Git host, dependency, signing key, reviewer, and rollback/freeze attacks.
  - Install/update UI distinguishes origin, content digest, publisher signature, marketplace review, reproducibility, and runtime permissions.
  - Revoked or identity-changing candidates cannot activate silently; offline policy and recovery are explicit.
  - The format supports reproducible artifacts and future provider-package attestations without coupling protocol compatibility to one marketplace.

### Z2-E2: Migration inventory large-asset and language-aware analysis

Suggested issue title: `Make plugin migration inventory scale to real assets and native/wrapped behavior`

- Class: post-v1 migration tooling; improves adoption but never becomes an approval control
- Depends on: B7/C9/D6/F6 evidence
- Scope: separate bounded semantic reads from streaming content identity so large inert assets do not block an entire report; add language/native provenance analysis and reviewed author worksheets for wrapped CLIs, services, generated QML, and composed risks.
- Acceptance criteria:
  - The six F6 large-preview/font repositories produce bounded advisory reports without allocating or decoding unbounded content and without weakening descriptor identity/race checks or total-work ceilings.
  - Docker Monitor's Docker authority and Textify's Rust capture/OCR/clipboard path are reported or explicitly require a durable author decision.
  - Archive, submodule, native dependency, generated-source, special-file, symlink, and runtime-download behavior is represented without execution.
  - False-positive annotations cannot suppress runtime enforcement or turn a clean report into a grant/safety claim.
  - Reports remain deterministic, identity-bound, schema-v1-unsafe, machine-readable, and diffable across revisions.

### Z2-E3: Ecosystem migration pilots and provider prioritization

Suggested issue title: `Migrate one real local widget, overlay, and authenticated service to schema v2`

- Class: post-v1 adoption milestone
- Depends on: Z2-A1–A6 and the provider/portal items required by the selected plugins
- Scope: work with authors to convert pinned real plugins while retaining their QML and product behavior; use the F6 worksheet to prioritize API gaps rather than adding generic escape hatches.
- Acceptance criteria:
  - One local-status widget, one expressive transparent overlay/slide-out, and one authenticated service install and run through the production path in the VM.
  - Before/after source maps identify reusable QML/models, replaced root surfaces, exact provider operations, user decisions, and unsupported behavior.
  - Each migration includes denial, update expansion, revocation, crash, resource, visual, accessibility-status, and removal-cleanup evidence.
  - New capability contracts land separately with adversarial tests; migration convenience does not broaden ambient authority.

## Issue creation checklist

Before posting any item externally:

- Replace node names with links to the final discussion/PR commits and immutable evidence.
- Confirm whether it is still an activation blocker or has become completed work during G4.
- Assign one owning component and avoid combining unrelated providers merely because they share a representative plugin.
- State the threat boundary, unsupported behavior, feature flag, package/VM requirements, and whether graphical testing must run in a disposable VM.
- Include focused Debug/Release/sanitizer/adversarial tests and a rollback/recovery expectation proportional to the authority.
- Link dependency issues explicitly and leave the issue blocked until their acceptance criteria close.
- Never phrase static inventory, signing, marketplace review, manifest declaration, or SDK use as runtime enforcement.
