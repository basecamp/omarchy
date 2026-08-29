# Draft PR: add a feature-gated secure plugin reference runtime

> Draft reference PR for architecture and security-boundary review. It is safe to open as a GitHub draft after explicit user review, but it must stay draft and must not merge while package-repository ownership, production-host composition, live activation, and general release-readiness gates remain open. Those limitations are part of the proposed PR body and must not be removed to make the branch appear production-ready.

This is a deliberately broad reference branch: 355 files and about 51,000 added lines include reference contracts, adversarial proofs, representative fixtures, historical spike evidence, and the execution ledger. Reviewers should use the linked review order below and may request stacked implementation PRs after the boundary is accepted; opening this draft is not a request for line-by-line merge approval of the whole branch.

Proposed base: upstream `basecamp/omarchy:quattro`. This candidate is synchronized through merge base `468b511249b1a341311c46f5a7cf81aa5bc5af92`. At publication preflight, upstream `7d58bb9a` was 11 commits ahead of merge base `468b5112`; the changed paths had no overlap and the merge tree was conflict-free, with no plugin-boundary or activation-assumption change. That unrelated drift is intentionally not merged into this exact package-proof candidate. Cross-fork head: `jacob-vincent-mink/omarchy:plugin-security-model`.

Related [architecture discussion](DISCUSSION_URL_TO_BE_INSERTED_AFTER_CREATION).

## Summary

This PR adds independently exercised reference components and vertical slices for moving third-party arbitrary QML outside `omarchy-shell`, transporting its rendered output into host-owned surfaces, and routing selected effects through authenticated, explicitly granted operations. The installed host does not yet compose those pieces into a live product path.

It does not replace the current schema-v1 plugin path. Legacy QML remains explicitly unsafe/unmigrated, and the reference native host deliberately reports unavailable until production composition and fresh-ISO acceptance are complete.

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
- A directly tested whole-policy permission-review implementation with full identity and diff, explicit required/optional grant or denial, no unattended consent, plus a redacted human audit inspector; neither inspector is exposed through the end-user router.
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

See [`plugin-security-f6-representative-migrations.md`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f6-representative-migrations.md) and the machine-readable [`representative-migration-outcomes.json`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/evidence/plugin-security-f6/representative-migration-outcomes.json).

## Permission and update UX

The directly tested `omarchy-plugin-permission-store review` reference binary shows the canonical plugin ID, full revision and policy digests, generation, active/candidate target, stable capability wording, exact scope, required/optional status, inherited grant state, and the complete delta. Decision-bearing changes require typing exactly `grant` or `deny` for each capability. The CLI gathers the complete review before its first write, so cancellation cannot persist a partial decision. Non-TTY review, `--yes`, and caller-selected audit actors fail closed. It is not advertised through the end-user `omarchy` router on this reference branch.

The directly tested `omarchy-plugin-audit-store` reference binary renders trusted redacted events using stable outcome/action/decision vocabulary and full plugin/revision identity. It does not include plugin messages, paths, URLs, storage keys/values, tokens, notification content, or provider payloads, and it is not advertised through the end-user router on this reference branch.

## Testing

The branch contains focused Debug, Release, ASan/UBSan, adversarial, fault-injection, stress, real-kernel, package, CLI, offscreen visual, and graphical acceptance entry points. The linked review guide below points to the principal contracts, vertical slices, hardening evidence, and release limitations; the work graph remains an execution ledger rather than a complete evidence index.

Final PR candidate `0dac331a8611c669801924394a2f28d94430e957` was built from a clean detached clone by the companion Arch recipe with checks enabled. Its Release package check passed 55/55 aggregate CTests, including the deterministic 10,000-case envelope/resource-cap exhaustion proof. The resulting `omarchy-dev-4.0.0.r1957.g0dac331-1-x86_64.pkg.tar.zst` has SHA-256 `137b70b28e69a62f01d6923d949b40f6e0db318ed868fa01a5d0ab4f58e60208`; the archive verifier and its negative mutation suite both passed. The installed `Omarchy.PluginHost` module dynamically loaded both `PluginHostInfo` and `RemotePluginSurface` while preserving their unavailable/disconnected feature-gated state. The archive has no install script or enablement symlink, and focused shell tests confirm no first-run, migration, or end-user activation path.

The final candidate passed fresh outside-confinement Debug and Release aggregates at 55/55 CTests. Separately, the repaired Release brokered-action teardown boundary had passed 100/100 fake-launch and 100/100 real-Bubblewrap repetitions during the earlier stress campaign. Five focused repository/plugin/QML tests and `./test/cli` passed. `./test/shell` reported seven failing files out of 212, none plugin-security-related; the G4 evidence classifies them as companion-repository version skew, managed-host/environment contamination, or tests that passed in isolation. They remain visible rather than being presented as an all-green shell suite.

The official ISO helper invokes `makepkg --nodeps`, so its builder image must explicitly provision the recipe's native `makedepends`; metadata alone does not make that hosted build reproducible. The privileged package container is also incompatible with the full nested-Bubblewrap, user-session, and display-dependent `check()` suite. The ephemeral ISO workflow may use `--nocheck`, but only alongside separately recorded complete Debug and Release native-suite results plus archive and negative-verifier results for the exact same candidate. The `--nocheck` package step is not counted as test evidence.

Hosted run [`33221534246`](https://github.com/jacob-vincent-mink/omarchy/actions/runs/33221534246) pinned candidate `0dac331a`, official ISO/package commits, and both Arch image digests. Its package-container `--nocheck` adaptation remains separate from the candidate's independently passing Debug and Release 55/55 suites. The run also logs an exact observation-only harness patch combining Tesseract PSM 6 and PSM 3 after the official PSM 6 path reproducibly omitted visibly selected green installer text. Artifact `f5-fresh-iso-0dac331a8611c669801924394a2f28d94430e957` records ISO SHA-256 `05b0a0bc7ed2e948c7f331a60ff01b17755edc61ce4b503336d794c63172696f` and package `4.0.0.r1.g0dac331-1` SHA-256 `98d8ca0b000292f61d6b51a4011513b97efc43d42d244c7c3ef113e4fcbbdfb9`. Both verifiers and all seven plugin-specific VM assertions passed, including exact installed identity, direct-worker denial, disabled/inactive service, graphical bridge presence, and unavailable QML state. The overall acceptance process still exited 1 on five exact known non-plugin baseline failures, recorded separately from `plugin_acceptance=pass`; this closes the dormant/reference VM gate, not production activation or general release readiness.

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
- The reference permission/audit inspectors have no end-user `omarchy` command route, and the reference user service remains disabled and inactive.
- The exact-candidate clean-source Arch archive proves package shape, checks, and absence of an activation path, but its companion recipe patch is not committed in `omarchy-pkgs`.
- The official hosted helper uses `--nodeps`, its builder image does not yet guarantee the new native `makedepends`, and its privileged container cannot run the full nested-sandbox/session/display package checks. A hosted `--nocheck` archive therefore requires separate exact-candidate native-suite evidence.
- The pinned fresh-ISO run proves exact package identity, dormant service state, direct-worker denial, graphical bridge presence, and unavailable QML import. It does not prove a compositor-owned live plugin surface or end-to-end activation, and its overall acceptance process retained five exact known non-plugin baseline failures.
- The checked-in PNGs are real offscreen Qt Quick output, not screenshots of a live layer-shell surface.
- Only four capability families are implemented. Network, general files, credentials, clipboard reads, capture, input injection, devices, media control, package management, compositor mutation, URL handlers, and real authenticated services remain denied/unimplemented.
- Schema-v1 remains arbitrary trusted host code. This PR does not make an existing plugin safe by adding permissions to its current manifest.

These limitations keep the PR in reference/proof status. The dormant/reference fresh-ISO gate passed, but production activation should remain feature-gated until host composition, committed package ownership, and live production-path acceptance pass.

## Rollout and compatibility

This PR is intended to establish the contracts and reference boundary before changing user defaults. Follow-up work should integrate the production host, land package ownership, complete the disposable-VM gate, add the author SDK and developer workflow, then migrate capability families one reviewed provider/portal at a time.

Legacy schema-v1 needs an explicit `unsafe.host-code` posture or refusal to load. Existing installations need a separately agreed transition policy. A clearly unsafe host-extension/developer mode should remain available for users who intentionally want arbitrary in-process QML, but it must never be described as granularly sandboxed.

## Review guide

Suggested review order:

1. Start with the [`trust map`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-a0-trust-map.md), then the frozen [`wire envelope`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-a2-envelope.md), [`capability contract`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-b2-capability-contract.md), and [`render contract`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-b4-render-contract.md).
2. Review Bubblewrap identity and lifetime in [`A2`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-a2-bwrap-identity.md), sandbox policy in [`B5`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-b5-sandbox-policy.md), and authenticated channel integration in [`D1`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-d1-channel-integration.md).
3. Follow arbitrary-QML rendering through the [`worker`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-c5-qml-worker.md), [`frame loop`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-d2-render-integration.md), and [`surface/input host`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-d3-surface-host.md).
4. Review broker authorization and audit-before-effect in [`D4`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-d4-audited-broker-runtime.md), then exercise the [`E0 lifecycle slice`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e0-headless-slice.md), [`E4 update/revocation proof`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e4-update-revocation.md), and [`E5 update hardening`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e5-update-hardening.md).
5. Inspect the executable vertical slices for the [`embedded bar`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e1-embedded-bar.md), [`expressive overlay`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e2-expressive-surface.md), and [`brokered action`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-e3-brokered-action.md).
6. Read the focused hostile campaigns for [`F0 sandbox/deputy`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f0-sandbox-deputy-proof.md), [`F1 exhaustion`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f1-exhaustion-proof.md), [`F2 rendering`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f2-render-proof.md), [`F3 lifecycle/crash`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f3-lifecycle-crash-proof.md), and [`F4 permission/audit UX`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f4-permission-audit-ux.md).
7. Finish with the [`package proof`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f5-package-review.md), [`install-surface audit`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-g4-install-surface-audit.md), [`release gate`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-g4-release-gate.md), and [`20-plugin migration outcomes`](https://github.com/jacob-vincent-mink/omarchy/blob/0dac331a8611c669801924394a2f28d94430e957/plans/plugin-security-f6-representative-migrations.md).

Questions requiring maintainer decisions are collected in the [architecture discussion](DISCUSSION_URL_TO_BE_INSERTED_AFTER_CREATION). Deferred capabilities should not be added to this PR merely to make a representative plugin pass; each should retain deny-by-default behavior until its provider or portal has its own reviewed contract and UX.
