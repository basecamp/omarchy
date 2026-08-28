# Draft PR: add a feature-gated secure plugin reference runtime

> Draft only. Do not open this PR until G4 closes. The package-repository, fresh-ISO/VM, and production-host limitations are part of the proposed PR body and must not be removed to make the branch appear production-ready.

Proposed base: the protected `jacob-vincent-mink/omarchy:quattro` branch, whose current history is merged into this branch. Proposed head: `jacob-vincent-mink/omarchy:plugin-security-model`.

## Summary

This PR adds a feature-gated reference implementation for running third-party arbitrary QML outside `omarchy-shell`, rendering it through host-owned surfaces, and brokering every system effect through authenticated, explicitly granted operations.

It does not replace the current schema-v1 plugin path. Legacy QML remains explicitly unsafe/unmigrated, and the installed native host deliberately reports unavailable until production composition and fresh-ISO acceptance are complete.

## Why

Schema-v1 plugins execute in the trusted shell process with the user's session authority. Path validation, warnings, and manifest permissions cannot make that code granularly safe because the plugin can directly import host APIs, execute processes, access files and session services, create privileged surfaces, inspect injected shell objects, exhaust or crash the shell, and bypass any voluntary broker API.

The reference boundary preserves arbitrary QML rather than replacing it with a component library:

```text
sandboxed plugin QML --bounded pixels/input--> trusted surface host
sandboxed plugin QML --typed request--------> authenticated broker/provider
sandboxed plugin QML --lifecycle------------> supervisor/revision/grant authority
```

The worker controls its scene graph and pixels. Omarchy controls identity, immutable source, surface role and placement, focus/input policy, frame resources, permission state, provider effects, audit, health, and teardown.

## Included

- Strict schema-v2 manifest parsing, canonical identities, bounded content walks, feature gating, and explicit schema-v1 unsafe classification.
- Immutable content-addressed revisions, atomic activation/rollback/recovery, owner-only grant/audit stores, exact generation and policy binding, and staged permission-expanding updates.
- A deny-by-default Bubblewrap launcher with isolated user/PID/mount/IPC/UTS/network namespaces, minimal read-only runtime, filtered environment, no capabilities, seccomp, resource scopes, pidfds, bounded teardown, and exact FD 3/4/5 channel setup.
- A fixed 40-byte versioned wire envelope, role-specific `SOCK_SEQPACKET` channels, kernel credential and pidfd lifetime checks, negotiation/readiness, bounded correlations, descriptor policy, and malicious-peer fixtures.
- A separate Qt Quick worker using `QQuickRenderControl`, strict imports/object bounds, a 64 MiB decoded-image allocation ceiling, software rendering, host-created two-slot shared memory, bounded frame/input schemas, and trusted-copy presentation.
- Host-owned surface admission, placement, dimensions, monitor identity, DPR, pacing, focus, capture, input regions, lock-screen policy, inspection, and termination seams.
- A closed broker with `storage.private@1`, `notifications.send@1`, `audio.play-cue@1`, and `service.fake-status@1`; exact request/result bounds; audit-before-effect; cancellation, revocation, handles, and poisoned-state behavior.
- Whole-policy permission review with full identity and diff, explicit required/optional grant or denial, no unattended consent, plus a redacted human audit inspector.
- Health, resource limits, request/surface accounting, crash backoff, disable/remove/reinstall behavior, stale-channel cleanup, and restart recovery.
- Pomodoro, transparent pet, and fake authenticated-service fixtures proving arbitrary-QML bar, overlay, and brokered-action paths.
- Report-only migration inventory and a pinned 20-plugin today-to-tomorrow matrix.

## Security evidence

The focused campaigns cover:

- Denial of real home, sibling plugin state, direct IPv4, session D-Bus, ordinary Wayland, agent sockets and variables, unexpected descriptors, descendants, and writes to the immutable revision.
- Forged plugin identity, crossed dispatcher/grant identity, stale generation, wrong role, descendant credentials, post-exit endpoint holders, invalid pidfds, descriptor floods, malformed/oversized envelopes, replayed/invalid frames, and unknown operations.
- Scope expansion, missing/expired/wrong gestures, ungranted optional operations, stale handles, audit failure, provider output bounds, reentry, cancellation, and revocation.
- Frame/request/input/surface rates, memory/scratch/task policy, output/descriptor pressure, crash loops, restart storms, health failure, ambiguous teardown, and stale-resource cleanup.
- Install, enable, staged update, approval/denial, activation and promotion faults, rollback, disable, revoke, remove, worker crash, broker restart, shell/supervisor recovery, reinstall, and downgrade/rebuild identity checks.

The proof campaigns found and fixed real issues, including a cross-plugin dispatcher/grant confused-deputy seam, DPR2 rendering/input scaling, unbounded sequential request starts, retained lifecycle authority after corrupt recovery, partial permission-review cancellation, stack exhaustion in a clean Release package build, compressed-image decoded-allocation amplification, and a teardown race that treated pidfd exit readiness as proof that the direct child was already reapable. The repaired teardown path uses bounded `WNOHANG` retries and passed 100/100 fake-launch plus 100/100 real-Bubblewrap repetitions after fresh Debug and Release aggregates.

## Arbitrary-QML compatibility evidence

The unchanged representative QML scenes prove custom layout, animation, alpha, clipping, irregular input regions, click-through behavior, bounded pointer/touch capture, and no retained keyboard focus. Host placement and pacing remain authoritative.

The worker fixes Qt image decoding at 64 MiB, matching the largest permitted 4,096 by 4,096 RGBA surface. Its focused corpus proves an ordinary PNG still decodes, a compressed 4,097-square PNG smaller than 1 MiB cannot allocate its 67 MiB decoded output, and repeated truncated or unsupported inputs remain rejected.

Checked-in visual artifacts cover a 320×180 transparent pet at DPR1, the same logical pet at 640×360 DPR2, and Pomodoro layouts at 180×48 and 280×64. One local sample measured software render p95 at 139 µs Debug, 319 µs Release, and 466 µs under ASan/UBSan; trusted-copy p95 was 15–31 µs; input-to-changed-frame was approximately 66–68 ms. These are regression observations, not end-to-end compositor latency or product guarantees.

The version-1 software profile does not support all Qt Quick effects. `ShaderEffect`, particles, restricted GPU rendering, accessibility, IME, drag and drop, plugin-owned popups, and cursor semantics remain follow-up work. Unsupported behavior fails or remains unavailable; it is not granted ambient host authority.

## Migration evidence

The pinned study covers 20 real repositories selected from a 1,575-source marketplace snapshot: bar widgets, panels and slide-outs, overlays/capture UI, services, filesystem, network, notifications, media, credentials, clipboard/input, device integrations, Docker, package updates, plugin management, and a full shell suite.

- Fourteen repositories produced deterministic advisory scan snapshots.
- Six remained inventory-blocked because a preview/documentation image or font exceeded the current 1 MiB per-file bound.
- Manual review caught effective Docker authority and Rust capture/OCR/clipboard behavior that successful static scans missed.
- Every mapping preserves arbitrary QML where the product remains an ordinary plugin.
- Sensitive behavior maps to future reviewed providers or portals; `@future` names are design placeholders and are not registered capabilities.
- Plugin management remains an Omarchy-owned lifecycle product, and a complete shell suite remains a separate trusted-host class or decomposition project.

See [`plugin-security-f6-representative-migrations.md`](https://github.com/jacob-vincent-mink/omarchy/blob/plugin-security-model/plans/plugin-security-f6-representative-migrations.md) and the machine-readable [`representative-migration-outcomes.json`](https://github.com/jacob-vincent-mink/omarchy/blob/plugin-security-model/plans/evidence/plugin-security-f6/representative-migration-outcomes.json).

## Permission and update UX

`omarchy plugin permission review` shows the canonical plugin ID, full revision and policy digests, generation, active/candidate target, stable capability wording, exact scope, required/optional status, inherited grant state, and the complete delta. Decision-bearing changes require typing exactly `grant` or `deny` for each capability. The CLI gathers the complete review before its first write, so cancellation cannot persist a partial decision. Non-TTY review, `--yes`, and caller-selected audit actors fail closed.

`omarchy plugin audit` renders trusted redacted events using stable outcome/action/decision vocabulary and full plugin/revision identity. It does not include plugin messages, paths, URLs, storage keys/values, tokens, notification content, or provider payloads.

## Testing

The branch contains focused Debug, Release, ASan/UBSan, adversarial, fault-injection, stress, real-kernel, package, CLI, offscreen visual, and graphical acceptance entry points. The work graph links each component and proof node to its evidence document.

The final code candidate `7aaa9b4883d20f4c5d054e9ef281a7feb06d1655` was built from a clean detached clone by the companion Arch recipe with checks enabled. Its Release package check passed 54/54 aggregate CTests. The resulting `omarchy-dev-4.0.0.r1946.g7aaa9b4-1-x86_64.pkg.tar.zst` has SHA-256 `7f85d031571eb5d7a1cd8d1144abf06260a834a001b17f8f90a805e5bb6874a8`; the archive verifier and its negative mutation suite both passed. The installed `Omarchy.PluginHost` module dynamically loads both `PluginHostInfo` and `RemotePluginSurface` while preserving their unavailable/disconnected feature-gated state.

After the current protected `quattro` merge, fresh outside-confinement Debug and Release builds each passed 54/54 native CTests. The Release brokered-action teardown boundary passed 100/100 fake-launch and 100/100 real-Bubblewrap repetitions. Five focused repository/plugin/QML tests and `./test/cli` passed. `./test/shell` reported seven failing files out of 212, none plugin-security-related; the G4 evidence classifies them as companion-repository version skew, managed-host/environment contamination, or tests that passed in isolation. They remain visible rather than being presented as an all-green shell suite.

Representative commands:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build/plugin-runtime -j2
ctest --test-dir build/plugin-runtime --output-on-failure

native/plugin-runtime/proof-exhaustion/run_campaign.sh /tmp/omarchy-plugin-f1-debug
cmake -S native/plugin-runtime/proof-campaigns/sandbox-deputy -B /tmp/omarchy-plugin-f0 -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-f0 --target omarchy-plugin-f0-proof -j2

cmake -S native/plugin-runtime/render-proof -B /tmp/omarchy-plugin-f2 -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-f2 -j2
ctest --test-dir /tmp/omarchy-plugin-f2 --output-on-failure

./test/cli
./test/shell
```

Real Bubblewrap credential/namespace checks must run outside managed development confinement. Graphical acceptance belongs in the disposable Omarchy VM and must not be run against the active desktop session.

## Current limitations and non-claims

- The installed `omarchy-plugin-host` is still an inert long-running skeleton and `PluginHostInfo.available` remains false.
- Aggregate registration includes the production trusted bridge, render session, surface host, expressive surface, representative fixtures, and vertical proofs, but `host/main.cpp` does not compose them into live discovery, activation, broker, or render pumping.
- Schema-v2 discovery/lifecycle is not switched into the current end-user install/enable/update commands.
- The clean-source Arch archive proves package shape and checks, but its companion recipe patch is not committed in `omarchy-pkgs`.
- No fresh `omarchy-iso` build/test has run in this workspace. There is no clean-install service log, live Quickshell import, compositor-owned plugin surface screenshot, or end-to-end installed activation proof.
- The checked-in PNGs are real offscreen Qt Quick output, not screenshots of a live layer-shell surface.
- Only four capability families are implemented. Network, general files, credentials, clipboard reads, capture, input injection, devices, media control, package management, compositor mutation, URL handlers, and real authenticated services remain denied/unimplemented.
- Schema-v1 remains arbitrary trusted host code. This PR does not make an existing plugin safe by adding permissions to its current manifest.

These limitations keep the PR in reference/proof status. Production activation should remain feature-gated until the host composition, clean package provenance, and fresh-ISO acceptance gates pass.

## Rollout and compatibility

This PR is intended to establish the contracts and reference boundary before changing user defaults. Follow-up work should integrate the production host, land package ownership, complete the disposable-VM gate, add the author SDK and developer workflow, then migrate capability families one reviewed provider/portal at a time.

Legacy schema-v1 needs an explicit `unsafe.host-code` posture or refusal to load. Existing installations need a separately agreed transition policy. A clearly unsafe host-extension/developer mode should remain available for users who intentionally want arbitrary in-process QML, but it must never be described as granularly sandboxed.

## Review guide

Suggested review order:

1. Trust map and frozen manifest/permission/wire/render contracts.
2. Bubblewrap launcher, exact FD identity, pidfd lifetime, seccomp, resource policy, and teardown.
3. Arbitrary-QML worker and untrusted frame/input handling.
4. Broker authorization, provider validation, grant/audit stores, handles, cancellation, and revocation.
5. Lifecycle activation/rollback/recovery and supervisor health/limits.
6. E1/E2/E3 vertical slices and F0–F4 adversarial campaigns.
7. Packaging/VM limitations and the 20-plugin migration outcomes.

Questions requiring maintainer decisions are collected in [`plugin-security-discussion-draft.md`](https://github.com/jacob-vincent-mink/omarchy/blob/plugin-security-model/plans/plugin-security-discussion-draft.md). Deferred capabilities should not be added to this PR merely to make a representative plugin pass; each should retain deny-by-default behavior until its provider or portal has its own reviewed contract and UX.
