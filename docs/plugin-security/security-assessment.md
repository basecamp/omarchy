# Plugin runtime security assessment

This document records adversarial review of the schema-v2 reference runtime. It distinguishes properties exercised against a real Bubblewrap process from design claims and from work that is not connected to the production host yet.

## Security objectives

The runtime must prevent plugin QML and bundled sidecars from exercising authority that was not granted to the exact installed plugin revision. A request reaching a provider must remain bound to the authenticated worker generation, a trusted capability definition, the granted operation and scope, current revocation state, and any required user gesture. Rendering and input must not let a plugin escape its host-owned surface. Failure, cancellation, update, and resource exhaustion must fail closed without leaving effects or reusable authority behind.

The attacker controls every byte in the plugin revision, including its manifest, QML, assets, and declared sidecars. The attacker can send malformed, replayed, reordered, oversized, and descriptor-bearing protocol messages and can intentionally crash or exhaust its worker. Trusted host code, the independently installed capability registry, broker adapters, the grant store, and the kernel isolation boundary are inside the trusted computing base. A separate malicious process already running as the same host user is not fully contained by Unix discretionary access controls and remains a distinct threat to evaluate during hardening.

## Current result

The reference implementation is fail-closed at its currently connected production boundary, but it is not ready for a live-capability claim. The product host launches with `DenyAllBroker`. Outside tests, no production component calls `dispatch_dynamic_invocation`, even though the worker can encode a dynamic invocation. Consequently, a VM can currently prove QML rendering, Bubblewrap isolation, sidecar containment, and broker denial, but it cannot prove that Radio Atlas, GitHub, AirPods, or another dynamically defined integration works through a live adapter.

This is a functional blocker rather than an authority bypass: external effects are denied, not accidentally permitted.

## Executed adversarial coverage

The focused security suite was run outside the development tool sandbox so `SO_PASSCRED`, user namespaces, network namespaces, pidfds, and systemd user scopes exercised the host kernel. The following passed:

- real Bubblewrap denial and namespace enforcement;
- worker endpoint credential capture and validation;
- descriptor injection and descriptor-flood quarantine;
- stale launch-generation rejection;
- malicious and descendant peer rejection;
- malformed envelope and bounded exhaustion corpora;
- broker operation, declaration, grant, scope, gesture, correlation, terminal, cancellation, and revocation checks;
- dynamic definition name, digest, generation, adapter, operation, and scope spoofing checks in the isolated activation gate;
- grant, revision, private-storage, and audit-store symlink rejection;
- sidecar role-descriptor closure;
- render and input sequence replay rejection and host clipping;
- real Bubblewrap brokered-action denial;
- systemd transient-scope attachment and teardown.

One surface-host test exits without a diagnostic in the existing build and remains unresolved. The update-transition fixture is incompatible with the exact dynamic-definition manifest fields and also remains unresolved. Both must be rebuilt and diagnosed before they count as passing evidence.

## Prioritized findings

### P0: Dynamic authorization is not connected to the product host

`product_host::launch` always supplies `DenyAllBroker`, and the dynamic dispatch gate has no non-test caller. Implement a production dispatcher that selects the exact reviewed `DynamicRevisionGrant`, trusted registry entry, scope validator, and adapter using the authenticated channel binding. A dynamic message must never fall back to a compiled capability with a similar name.

Add an end-to-end test that launches the installed worker in Bubblewrap, invokes from real QML, observes one effect in a fake-but-production-shaped adapter, revokes the grant, and proves a second invocation and any outstanding handle fail. Repeat with a stale revision, definition generation, adapter digest, expanded scope, replayed correlation, and forged payload reference.

### Closed: Prepared content was reopened by pathname at launch

Preparation previously hashed and verified `plugin_root`, then reopened that pathname at launch. Preparation now pins the verified directory with `O_NOFOLLOW`, transfers ownership of that descriptor with the prepared activation, and launch duplicates the pinned descriptor. An adversarial prepare-then-rename-and-replace test proves that activation retains the original directory.

Same-user mutation of files inside an owner-controlled pinned directory remains a residual risk. Production activation should accept only content-addressed revision-store trees and should verify their store record before passing the descriptor to Bubblewrap.

### P1: Provider confused-deputy constraints need a production contract

The isolated dynamic gate verifies operation, scope, adapter binding, and gesture before calling an adapter, but the adapter callback does not receive an explicit authenticated plugin/activation identity. If adapter instances or credentials are ever shared, this makes correct per-plugin resource selection depend on ambient adapter context.

Pass a broker-created authorization context to every adapter call containing the immutable activation binding, canonical capability reference, granted epoch, operation, and validated demand. Providers must derive account/device/resource access only from opaque handles in that context, never from plugin-supplied paths, executable names, account names, or credential identifiers. Test cross-plugin handle substitution and two simultaneous plugins with overlapping operations.

### P1: Revocation and update must cover dynamic in-flight work

Compiled broker operations have cancellation, terminal-state, epoch, and update-transition coverage. Dynamic dispatch is presently synchronous and isolated from the production lifecycle. Before enabling real network, device, or account providers, define cancellation and terminal semantics and prove revocation prevents queued work, streaming callbacks, cached handles, and retries from completing under an old epoch.

### P2: Same-sandbox sidecars expand the attack surface by design

Sidecars correctly do not inherit broker, control, or render descriptors, and remain inside the worker Bubblewrap and cgroup. They intentionally retain the launch seccomp filter, including `execve` and process creation, so they can supervise their own bounded subprocesses. This is compatible with the same-sandbox model but makes the declared sidecar executable and all parsers it exposes part of the untrusted workload.

A real Bubblewrap sidecar probe now verifies direct role descriptors are closed, parent role sockets cannot be reopened through `/proc/1/fd/{3,4,5}`, host and home canaries are absent, D-Bus and Wayland session authority is absent, and nested namespace creation is denied. This test also found and corrected a test-only policy mismatch: the sidecar Bubblewrap fixture had omitted production's `--disable-userns --assert-userns-disabled` flags.

Coverage still needs `pidfd_getfd`, Unix credential spoofing, explicit network-egress canaries, and bounded fork/exec exhaustion. Continue to treat private loopback, files, and sockets inside the sandbox as intentionally shared and therefore unsuitable for secrets between QML and its sidecars.

## Reusable campaign

`native/plugin-runtime/security-campaign/run_campaign.sh BUILD_DIRECTORY` runs the acceptance security set. It currently comprises 25 tests covering install validation, deterministic manifest mutations, wire and permission contracts, real Bubblewrap enforcement, sidecars, broker and QML APIs, render transport, providers, revision/grant/audit stores, authenticated channels, malicious peers, and bounded exhaustion. The first local production-kernel run passed 25 of 25 tests.

### P2: Render and input abuse requires sustained fuzzing

Sequence, generation, descriptor-count, mapping-size, region clipping, and object limits have deterministic coverage. Add long-running mutation corpora for allocation/frame/input interleavings, malicious alpha/input-region combinations, rapid surface churn, integer boundary dimensions and strides, and shared-memory mutation during host consumption. Run with ASan/UBSan and enforce CPU/memory/frame-rate budgets in the VM.

### P2: Capability-definition and manifest parsing need coverage-guided fuzzing

The parsers are bounded and reject duplicate JSON keys, unknown fields, symlinks, malformed UTF-8, excessive nesting, stale definition references, and expanded grants. Add libFuzzer targets for manifest parsing, definition loading, dynamic grant/invocation decoding, broker envelopes, and audit recovery. Seed them with every accepted winner manifest plus near-valid spoof cases.

### P3: Audit confidentiality and abuse policy is incomplete

Current broker audit records primarily capture metadata and byte counts, which limits direct secret leakage. Production adapters must prohibit request payloads, credentials, tokens, notification bodies, device identifiers, and returned content from entering audit records. Rate-limit repeated denial records so an untrusted plugin cannot turn auditing into a disk or privacy side channel, while retaining enough information for incident review.

## VM acceptance gate

Do not describe the winner ports as working with live capabilities until all of the following are captured from a disposable VM or an explicitly isolated parallel installation on the host:

1. The runtime package installs without replacing or activating the Omarchy 4.x legacy plugin path.
2. Schema-v2 activation is opt-in and uses separate revision, grant, state, audit, and socket roots.
3. Each winner renders and exercises every claimed live provider with a narrow grant; denial and revocation are demonstrated from the UI.
4. Network, filesystem, process, device, credential, compositor, D-Bus, Wayland, and descriptor escape probes fail from both QML and sidecars.
5. Update, rollback, crash, cancellation, provider timeout, audit failure, and cgroup exhaustion fail closed.
6. Two hostile plugins run concurrently without crossing state, handles, account/device selections, surfaces, or broker identities.
7. The full test corpus and sanitizer/fuzz campaigns run against the exact installed binaries and package contents.

The discussion and PR should be rewritten from this evidence after the production dynamic broker and at least one real provider complete this gate.
