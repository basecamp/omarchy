# PR draft: schema-v2 plugin security reference implementation

## Summary

This PR proposes a reference implementation of a secure schema-v2 plugin runtime. It is intentionally dormant and is not a production rollout. Ordinary users cannot activate it through the `omarchy` command router, the packaged user service remains disabled, discovery defaults to off, and the ordinary preview uses a deny-all broker. The only live-provider path requires both `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1` and `OMARCHY_PLUGIN_LIVE_LAB_ENABLED=I_ACCEPT_LAB_RISK`, an isolated grant/state/audit root, and a separately installed root-owned content-addressed lab bundle.

The implementation is included so the security model can be reviewed against running code rather than only an architecture document. Merging this reference would not make existing schema-v1 plugins safe, migrate user configuration, replace the current plugin directory, or authorize a production service. Schema-v1 remains the explicitly unsafe compatibility path in which plugin QML executes with the authority of the user session.

## What changes

The reference runtime adds a native host, sandboxed QML worker, immutable revision and activation model, permission and audit stores, authenticated role-separated channels, a capability broker, trusted providers, remote rendering, sidecar supervision, lifecycle recovery, adversarial fixtures, migration tooling, and a side-by-side live-testing harness under `native/plugin-runtime/`.

The security boundary is based on the following ownership split:

- The plugin owns its QML scene, local model, assets, animation, pixels inside its assigned surface, private sandbox files, and communication with its declared same-sandbox sidecars.
- Omarchy owns the immutable revision identity, activation generation, sandbox construction, host surface, placement, focus and input policy, frame limits, permission decisions, capability definitions, provider implementations, external effects, audit admission, revocation, and teardown.
- Plugin identity comes from the launch tuple and authenticated channel. It is never accepted from a request payload.
- Every effect outside the sandbox is a typed broker operation checked against the exact active revision, generation, manifest request, definition, operation, granted scope, current epoch, and any gesture requirement.

## Full QML remains the UI model

This does not replace plugin-authored QML with a declarative component library. A plugin still loads arbitrary Qt Quick in its own QML engine and can build custom controls, layouts, canvases, animations, transparent surfaces, slide-outs, desktop pets, and other nonstandard scenes. The worker renders into bounded shared-memory frames and the trusted host presents those pixels inside a host-owned surface envelope.

The change is authority, not visual authorship. Plugin QML no longer executes inside `omarchy-shell`, receives shell objects, imports ambient process or filesystem authority, creates privileged layer-shell surfaces, or connects to the normal session Wayland and D-Bus sockets. Omarchy constrains the surface role, monitor, size, z-order, focus, input region, frame rate, memory, and lifetime.

The current reference uses Qt software rendering. It proves arbitrary QML structure and custom pixels for the covered Qt Quick subset, but it does not support every visual feature. `ShaderEffect`, particles, some transformed text, restricted GPU rendering, multi-surface composition, accessibility semantics, and zero-copy transport remain future work. Plugins that require an unsupported profile should remain unmigrated rather than silently losing behavior.

## Manifest requests, capabilities, grants, and broker calls

A manifest permission is a request, not authority. Install or update parses the schema-v2 manifest, canonicalizes its requests, hashes the complete immutable tree, records a distinct source-request fingerprint, and stages a candidate activation. The user reviews required and optional requests before activation. `--yes`, omission, a plugin-selected name, or an update cannot create a grant.

Compiled capabilities cover stable Omarchy-owned operations such as `storage.private@1`, `notifications.send@1`, and `audio.play-cue@1`. Extensible capabilities use independently installed trusted definition documents. A definition binds a canonical name, generation, content digest, operations, scope grammar, adapter class and ABI, and implementation digest. A plugin may request only an installed definition and operation subset. It cannot define the provider contract that interprets its own permission.

The worker derives the capability or definition reference from the verified manifest and exposes bounded `runtime.invoke(...)` calls. QML does not supply its plugin id, revision, generation, grant epoch, definition digest, or adapter identity. The broker reconstructs those values from the authenticated activation, validates the operation-specific payload and demanded scope, compares them with the current grant and registry entry, durably admits a redacted audit record, and only then dispatches to a provider with a broker-created authorization context.

This mapping prevents two plugins from creating independently meaningful names such as `service.gh` and `cli.gh` and treating them as equivalent host authority. Extensibility belongs in the trusted registry: a future harness provider can publish a reviewed definition such as `bash.<harness>` with an exact executable, command grammar, argument bounds, resource selectors, adapter implementation, and revocation behavior. A free-form manifest string alone never creates that mapping.

## Optional permissions and permission-aware QML

Optional permissions are independently selectable and revocable. The worker receives a host-authenticated, read-only availability snapshot containing only operations that the plugin requested. QML can query `runtime.permissionState(capability, operation)` and react to `permissionsChanged` to hide, disable, or replace optional features.

The snapshot is ergonomic, not authoritative. It exposes neither other plugins nor grant-store internals, and a stale `GRANTED` display cannot authorize an operation. The broker rechecks the live grant and epoch on every call. The live permission fixture demonstrates initial `GRANTED` with zero change observations, exact revocation, audit decision `5`, and a subsequent `DENIED` state with one observation.

## Sidecars

Schema v2 may declare exact bundled sidecar executables by normalized relative path. The executable must be a regular executable file inside the immutable revision; bare names, host paths, `..`, symlinks, special files, and shell lookup are rejected. The worker starts only declared sidecars with `execve`, closes privileged descriptors, supervises and reaps them, and treats unexpected exit as a generation failure.

QML and declared sidecars share the same Bubblewrap sandbox, private files, Unix sockets, standard streams, and private loopback so plugin-local cooperation does not require broker calls. Sharing a sandbox does not grant external authority. Sidecars receive no broker, control, or render descriptor and cannot reopen those descriptors through `/proc`. A future direct sidecar broker endpoint would require its own authenticated protocol and permission binding.

Helpers whose purpose is to escape the sandbox are not sidecars. A GitHub `gh` helper, Radio network proxy, media player controller, or AirPods daemon belongs in a separately installed and reviewed provider because it holds network, credential, device, D-Bus, PipeWire, or host process authority.

## Native runtime and isolation

The native implementation uses fixed, negotiated `SOCK_SEQPACKET` roles for control, broker RPC, and render/input. Kernel credentials, pidfds, endpoint roles, revision, generation, sequence, correlation, descriptor count, and message size are checked before use. Malformed, replayed, reordered, stale, role-substituted, descendant, and descriptor-bearing messages fail closed.

The launcher pins `/usr/bin/bwrap` and the production worker path. The worker runs in new user, PID, mount, IPC, UTS, network, and cgroup namespaces with no Linux capabilities, no ambient home, network, D-Bus, Wayland, agents, credentials, or host executable lookup. It receives a read-only descriptor-pinned plugin revision, synthetic home, private temporary directories, bounded private state, a minimal runtime, seccomp policy, and systemd limits. Production preparation pins the verified revision directory descriptor with `O_NOFOLLOW` so a pathname replacement between verification and launch does not substitute content.

The trusted host owns shared-memory allocation and copies bounded frames before presentation. It rejects invalid dimensions, strides, mappings, roles, input regions, descriptors, generations, sequences, and frame rates while preserving the last valid frame. Plugin-controlled pixels are treated as untrusted visual content, not as authentication UI.

## Lifecycle, updates, and revocation

Install and update stage immutable content-addressed revisions. A new revision remains inert until validation, explicit permission review, and atomic activation complete. Expanded authority is never inherited silently. Failed candidates do not replace the active revision, and recovery uses durable revision and grant records rather than guessing from files on disk.

Disable, remove, rollback, update, crash, provider loss, and revocation invalidate the activation generation, poison retained broker references, cancel or deny outstanding work according to the operation contract, stop new dispatch, terminate the worker and sidecars, and tear down the generation cgroup. Dynamic provider calls receive an immutable authorization context containing the activation binding, canonical capability reference, validated grant epoch, operation, and scope so shared adapters cannot confuse one plugin's authority with another's.

The live-lab host supports one narrowly defined grant reduction while running. It applies broker and provider revocation before sending the reduced permission snapshot to QML. Expansion, binding drift, replacement, replay, and restart-required changes fail closed.

## Representative plugin ports

The migration study covers 20 pinned real plugins from a 1,575-source marketplace snapshot and includes secure ports for the first competition winners:

- Radio Atlas preserves its rotatable globe, markers, model, animations, ranking, and controls. Direct `curl`, proxy, player, socket, and compositor observation paths map to reviewed `network.fetch`, `media.play-stream`, private storage, and sanitized system-observation providers. The real Radio network and media providers are not complete, so live parity is not claimed.
- Omagotchi preserves its pixel-art pet, sprites, animation, care, aging, sleep, happiness, pointer behavior, and custom overlay QML. Persistence uses `storage.private`; sound and evolution notification use packaged-audio and notification capabilities. Ambient window climbing and package inspection are removed pending reviewed observation providers.
- AirPods preserves the custom panel and bounded device controls. Observation and control map to opaque user-selected device handles, but the privileged daemon is provider reference material rather than plugin-installed code or a sidecar. No AirPods hardware proof is claimed.
- The GitHub dashboard preserves its custom dashboard, sections, rows, and actions. Account reads, mark-read mutation, and opening a GitHub URL map to separate scoped providers. The plugin does not inherit `gh`, network, or credentials. Live account behavior is not claimed.

The Omagotchi port includes a strict decoder for the real `storage.private/read` response envelope: found byte, three reserved zero bytes, big-endian length, and bounded compact JSON. It rejects malformed envelopes and invalid or out-of-range state. A separate lab-only fixture, not the production entry point, performs an ordinary authorized write after restore.

The final host proof seeded generation 7/hunger 61, visibly restored it, and wrote generation 8/hunger 51. A fresh second launch visibly restored generation 8/hunger 51 and wrote generation 9/hunger 41. The raw state file remained mode `0600`, link count 1. Its SHA-256 changed from `b74f7f2d48a0c26be7e32206867c4984257cebb30b09ab75dae09c99cf75889c` to `c977a65adba2bdc50fe1f7b7947917f3ec895dcb2394bd2de9c7b5b217cbb5b2`, then `d2e7f1951865302a9db789440dece1bb1453a0ca97b140b937740b86f169b5f0`. Both launches have correlated successful read/write audit records and visible PNG evidence.

## Automated and adversarial results

The focused production-kernel security campaign passes 25 of 25 tests. It covers install validation, deterministic manifest mutation, wire and permission contracts, real Bubblewrap enforcement, sidecars, broker and QML APIs, render transport, providers, revision/grant/audit/private-state stores, authenticated channels, malicious peers, descriptor quarantine, and bounded exhaustion.

The real-Bubblewrap product E2E path passes 20 of 20 repeated runs. It launches immutable authorized, denied, and permission-aware QML through the production-shaped host and worker, verifies broker calls and terminal frames, proves allowed and denied frames differ, checks state and audit effects, revokes the optional permission, and requires an authenticated post-revocation frame.

The broader native reference aggregate has separate Debug and Release evidence, sanitizer coverage, fuzz smoke, repeated fake and real-Bubblewrap brokered-action runs, package archive verification, and the 10,000-envelope exhaustion corpus. Exact component results and environment exceptions remain documented under `docs/plugin-security/` rather than being compressed into a single readiness claim.

Malicious coverage includes:

- schema-v1 presented as secure, malformed or oversized manifests, duplicate keys, unknown fields, symlinks, special files, noncanonical paths, changed immutable trees, and undeclared sidecars;
- direct worker launch, untrusted worker selection, non-root or writable runtime paths, wrong worker or bundle digest, and modified installed artifacts;
- direct filesystem, network, process, D-Bus, Wayland, agent, credential, host-home, and cross-plugin access attempts;
- forged plugin, revision, generation, capability, definition generation/digest, adapter, operation, scope, gesture, correlation, sequence, role, credentials, and descriptor traffic;
- stale and replayed calls, cross-plugin handle substitution, descendant peers, descriptor floods, malformed render mappings, frame floods, sidecar descriptor inheritance, nested namespace creation, crash loops, and exhaustion.

Install-time violations are rejected before activation. Runtime violations are denied or terminate the offending generation without provider effect. Audit admission failure is effect-free.

## Reproducible live evidence

The final live proofs ran side-by-side on Omarchy 4.0.1 without replacing system files, changing the schema-v1 plugin directory, modifying `~/.config/omarchy/plugins`, or activating a production service. The root-owned bundle was installed only below `/opt/omarchy-plugin-security-lab/36b06e268e6d8bd51c8f64cfff34ca52a08790bb0cb6c3b710e3034a9f94000c`.

That bundle was built from the clean candidate immediately before the final rebase. After rebasing the complete series onto current `upstream/quattro`, a fresh clean Release build again passed the 25-test security campaign and 20 product E2E repetitions. The rebased binary was not installed over the recorded bundle, so the desktop evidence below remains attributed to `36b06e268e...` rather than being presented as evidence for an unrecorded replacement.

Bundle identity covers the relative path, mode, and digest of every installed host, worker, bridge, QML metadata, permission tool, audit tool, and provenance file. Launch separately pins worker SHA-256 `38ea7641b749e083a09f92d958752d6dcc80d9f747bcd74436f75bcc1923fd49`, rehashes it, and rejects symlinks, non-root ownership, writable path components, or a noncanonical bundle root.

Each scenario used a fresh immutable plugin copy and separate mode-0700 grant, private-state, audit, and evidence roots. CUA Driver captured exact-window JSON and PNGs; broker state and redacted audit records were exported independently; the live host, worker, and Bubblewrap process tree was recorded; and every file was hashed. No video is claimed.

The final semantic evidence manifest is `/tmp/omarchy-36b-final-20260829/evidence/SHA256SUMS`, whose SHA-256 is `3e47f4fabf9d554494d99a52501f7e442091686654620af043e15f359030cc8b` on the test host:

- Authorized startup visibly reached `AUTHORIZED`; `storage.private/write` and `storage.private/read` both have successful request and terminal audit records; the stored value is exactly `broker-round-trip`. Screenshot SHA-256: `f1f48d971a47762b4a182c2c668324d428ffbd705f9c4ab3f03440ef2c517178`. Audit SHA-256: `ad7bc4ed3d3f94b24fcac296d28b60a36b42d69f7d8d70832f620d5fc661c718`.
- Optional permission startup visibly showed `GRANTED` with zero observations. Screenshot SHA-256: `d61b6663ea94e4081f2430ff103c3878e6bd74c0a35b62580438689dd2e65a4f`.
- Exact revocation produced active epoch 2 and audit decision `5` before QML received the reduced snapshot. The UI then visibly showed `DENIED` with one observation. Final screenshot SHA-256: `f9ff47de0b32d214616004c3460e63f2bcccf82ee3240615f3b7fe64d4d1bb1f`. Permission audit SHA-256: `d50d0b0dee200d560468135fc187f2990b25ab4dd47b2c68062771b20c800206`.
- The authoritative denial fixture visibly rendered typed `DENIED`, recorded broker denial for an unrequested notification operation, and produced no external effect. Screenshot SHA-256: `6b4679f190a257f537a346268a492d8fe0d8103ae87f650aac41184359d78846`. Audit SHA-256: `3b509c72d2dcf6f857b3e7e1d91d617e3ebb710f23f4d2596951223105015203`.

The fresh-ISO VM gate separately proves dormant package installation, exact installed identity, direct-worker denial, disabled/inactive host service, graphical bridge presence, feature-gated labeling, and packaged QML import under Wayland. It does not yet reproduce the live-provider campaign inside the VM. The hosted aggregate also retains known non-plugin baseline failures, so neither the VM result nor the host-side lab is presented as general release readiness.

## CI adaptation

The native runtime needs Linux jobs with real user, PID, mount, IPC, UTS, network, and cgroup facilities; `SO_PASSCRED`, pidfds, Bubblewrap, systemd user scopes, Qt offscreen rendering, and a Wayland VM are not available in every generic build container. CI should split responsibilities rather than skip them silently:

- A normal unprivileged build job configures `BUILD_TESTING=ON` and runs deterministic unit, protocol, property, parser, store, broker, provider, QML, render, and malicious-peer tests.
- A Linux security job runs `native/plugin-runtime/security-campaign/run_campaign.sh` outside wrappers that prohibit user namespaces or credential passing and requires 25 of 25.
- A real-Bubblewrap product job runs the product E2E fixture repeatedly and requires 20 of 20, including the post-revocation frame.
- Sanitizer and bounded fuzz jobs use uniform compiler and executable-linker instrumentation across the selected tree. Exact sandbox helper processes that cannot admit LeakSanitizer remain uninstrumented and are covered independently.
- The package-builder container may use its explicitly logged `--nocheck` adaptation because nested sandbox, session, and display tests cannot run there. That build is not test evidence; package archives are verified separately, and the security and E2E jobs must already have passed the exact source candidate.
- A disposable-VM job installs the exact package/ISO artifacts, verifies hashes and dormant defaults, imports the installed QML module under Wayland, and runs graphical acceptance without touching a developer's live configuration.

These jobs should record the source commit, dirty-tree fingerprint, build configuration, package digest, bundle identity, worker digest, kernel, Qt version, and evidence manifest so host-only or bridge-only changes cannot reuse a worker-only identity.

## Known limitations and follow-up work

This PR does not enable production schema-v2 activation. Before rollout, the project still needs:

- production service packaging, ownership, shell integration, trusted permission UI, enable/disable/update commands, migration UX, and recovery policy reviewed as one product path;
- restricted GPU rendering or explicit runtime profiles, multi-surface composition, accessibility semantics, input-method coverage, high-DPI/multi-monitor testing, and compositor-specific ordinary-window policy;
- real bounded HTTPS and media providers for Radio Atlas, account and URI providers for GitHub, hardware-backed device providers for AirPods, and sanitized compositor/package observation where justified;
- provider-specific response codecs, pagination, timeouts, cancellation, streaming and cached-handle revocation, audit redaction/rate limiting, concurrent hostile-plugin isolation, and long-running mutation/fuzz campaigns;
- publisher provenance and signing policy beyond content identity and recorded origin;
- a disposable-VM live-provider run using exact installed binaries, plus a generally green fresh-ISO baseline.

Generic `bash.execute`, unrestricted host paths, ambient network, the normal Wayland socket, broad D-Bus access, and plugin-installed privileged services are not planned compatibility mechanisms. New integrations should extend the trusted capability registry with bounded definitions and providers.

## Rollout proposal

1. Review the threat model, authority boundaries, capability/definition model, render transport, provider context, lifecycle, and test evidence while the implementation remains dormant.
2. Land only the reference runtime and authoring/migration tools if reviewers agree the boundary is sound. Keep schema v2 unavailable to ordinary users.
3. Complete one production-quality provider family and the trusted permission/activation UI, then repeat the exact package, security, E2E, and disposable-VM live campaign.
4. Offer schema v2 as an explicit experimental mode with separate roots and clear runtime-profile labels. Do not reinterpret schema-v1 plugins as sandboxed.
5. Migrate representative plugins and competition winners with before/after behavior maps. Expand the provider registry only through reviewed Omarchy-owned definitions and implementations.
6. Make secure mode the default for new third-party plugins only after the product host, recovery, accessibility, compositor, provider, and VM gates are complete. Retain unsafe legacy mode only with an indivisible full-session warning until it can be removed.

## Reviewer guide

Reviewers can approach this PR by boundary rather than file count:

1. Start with `docs/plugin-security/architecture.md` and `docs/plugin-security/security-assessment.md`. Confirm the threat model and the distinction between arbitrary pixels and host authority.
2. Review manifest and permission contracts, canonical fingerprints, trusted definitions, grant storage, and update inheritance. Try to find a path from a manifest string to authority without an installed registry entry and explicit grant.
3. Review launcher, descriptor pinning, Bubblewrap arguments, seccomp, systemd limits, role channels, peer credentials, pidfds, and descriptor quarantine. Try replacement, descendant, replay, and inherited-FD cases.
4. Review broker and provider ordering: authenticate, validate, authorize current epoch, admit durable redacted audit, then effect. Check every failure and cancellation path for pre-audit or post-revocation effects.
5. Review render and input as hostile data. Confirm trusted allocation, bounded copies, surface-role enforcement, focus restrictions, pacing, last-valid-frame behavior, and teardown.
6. Review sidecars as untrusted same-sandbox code. Confirm exact immutable executable selection, no shell lookup, no privileged role descriptors, supervision, reaping, and generation teardown.
7. Run the 25-test security campaign and 20-run real-Bubblewrap E2E lane on a suitable Linux host. Rebuild a clean bundle and verify that changing any installed artifact changes bundle identity while the worker pin remains independently checked.
8. Use the side-by-side lab or disposable VM only with isolated roots. Compare visible terminal states with audit, state, grant epoch, process tree, and hashes; do not accept screenshots alone.

The requested review outcome is a decision on the model and its enforcement seams, not approval to turn it on for users in this PR.
