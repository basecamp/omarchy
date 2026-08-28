# F2 rendering fidelity, latency, DPI, and monitor proof

## Outcome

F2 exercises the real arbitrary-QML worker, shared-memory frame consumer, D3 surface policy, E2 expressive placement registry, and the exact C10 Pomodoro and pet fixtures. The proof keeps plugin QML unrestricted as UI code while measuring only the authority-free software-render path.

The visual review found and fixed one concrete worker defect: a DPR 2 allocation produced a correctly sized physical buffer but rendered the QML scene into only the logical-size upper-left portion. The worker now gives its trusted scene root the host-selected DPR transform, renders into the full physical buffer, and translates authenticated logical input coordinates into physical scene coordinates. A worker-unit pixel-bound test and a representative pet input/render test freeze the correction.

## Reproducible proof

Configure and run the proof directly:

```bash
cmake -S native/plugin-runtime/render-proof -B /tmp/omarchy-f2-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-f2-debug --target omarchy-plugin-render-proof-test omarchy-plugin-expressive-surface-test omarchy-plugin-surface-host-test omarchy-plugin-render-session-test omarchy-plugin-trusted-bridge-test omarchy-plugin-embedded-bar-test -j2
ctest --test-dir /tmp/omarchy-f2-debug --output-on-failure -R '^(plugin-render-fidelity-proof|plugin-expressive-surface|plugin-surface-host|plugin-render-session|plugin-trusted-bridge|plugin-embedded-bar-slice)$'
```

The proof pins `QT_QPA_PLATFORM=offscreen`, `QSG_RHI_BACKEND=software`, and full-frame software updates. It generates review artifacts in `/tmp/omarchy-f2-debug/artifacts` and fails when its deliberately broad regression ceilings are exceeded: render p95 below 100 ms, render maximum below 250 ms, trusted shared-memory copy p95 below 50 ms, and click-to-first-changed-frame below 250 ms.

Those are regression ceilings, not performance promises. Render measurements cover `WorkerRuntime::render()` and software scene-graph work. Copy measurements cover the bounded trusted `FrameConsumer` copy. They exclude worker/host scheduling, authenticated datagram transit, compositor upload, presentation, and display latency. Click-to-frame includes the fixture animation timer and 4 ms polling interval; it proves bounded visible response rather than raw input dispatch latency.

## Measured local sample

All values are microseconds from one local run on 2026-08-28 and are recorded as observations, not release guarantees.

| Build | Render p50 | Render p95 | Render max | Trusted copy p95 | Input to changed frame |
| --- | ---: | ---: | ---: | ---: | ---: |
| Debug | 76 | 139 | 172 | 17 | 68,213 |
| Release | 92 | 319 | 441 | 15 | 67,894 |
| ASan/UBSan | 346 | 466 | 583 | 31 | 66,095 |

The host-owned 30 FPS budget is covered by `plugin-surface-host` with a monotonic injected clock: early frames are nonfatal/coalesced, the next frame is accepted after 33,333,334 ns, and clock rollback fails closed. The F2 worker loop intentionally samples faster than that budget to measure software-render cost independently of host pacing.

## Visual inspection

The generated images were inspected at original resolution:

- [Pet at DPR 1](evidence/plugin-security-f2/pet-dpr1.png) is a 320×180 RGBA frame. The checkerboard remains visible outside the pet, demonstrating transparent background and clipping at the allocation boundary.
- [Pet at DPR 2](evidence/plugin-security-f2/pet-dpr2.png) is a 640×360 RGBA frame for the same 320×180 logical surface. The pet and its alpha bounds occupy twice the physical dimensions, while logical input at the original pet coordinates still starts animation and ends unfocused.
- [Narrow Pomodoro](evidence/plugin-security-f2/pomodoro-narrow.png) is 180×48. `READY` and `25:00` remain legible with no edge clipping or overlap.
- [Wide Pomodoro](evidence/plugin-security-f2/pomodoro-wide.png) is 280×64. The same arbitrary QML recenters without stretching or introducing host UI.

The proof also moves the trusted placement identity from monitor 11 at 1920×1080 to monitor 12 at 2560×1440 and rejects out-of-bounds placement through the existing E2 registry. This validates host-owned monitor identity and geometry arithmetic, not a live compositor output transition.

## Automated evidence

- Debug: six focused F2/E1/E2/D2/D3/bridge tests passed.
- Release: the same six tests passed.
- ASan/UBSan with leak checking disabled for Qt process-global allocations: the same six tests passed.
- Worker Debug and worker ASan/UBSan: `plugin-worker-runtime` passed with the new DPR physical-coverage regression.
- `git diff --check` passed for the atomic change.

## Remaining installed-system proof

This repository does not yet install and activate the secure host/worker path in the running Omarchy session. Consequently F2 cannot honestly claim compositor presentation latency, live monitor hotplug behavior, fractional-DPR behavior on physical outputs, GPU-versus-software comparison, or shell-level visual placement. Those belong to the F5 disposable-VM/fresh-install proof after packaging and systemd/Quickshell integration exist. The checked-in images are real Qt Quick software-render output from the representative fixtures, but they are not screenshots of a live layer-shell surface.
