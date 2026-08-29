# A4: Secure plugin test and disposable-VM integration survey

## Result

The secure plugin implementation needs eight distinct verification layers. The existing Omarchy runners cover CLI routing, headless shell logic, compositor-gated shell smoke tests, and installed graphical acceptance. Native Qt tests, protocol fuzzing, security probes, and rendering benchmarks do not yet have repository-wide entry points; `B0` and `B6` must establish those alongside the native build rather than hiding them in shell tests.

No single aggregate command currently exercises every layer. `./test/all` intentionally runs only `./test/cli` and `./test/shell`; it does not run native CTest, graphical acceptance, package builds, fuzzers, benchmarks, or manual visual inspection.

## Exact entry points

### Existing local tests

| Layer | Source location | Command | Use for secure plugins |
| --- | --- | --- | --- |
| CLI router and metadata | `test/cli` | `./test/cli` | Route resolution, help, aliases, hidden internal commands, command metadata, argument errors, and proof that `--help` never executes a security-sensitive command |
| Headless shell and command integration | `test/shell.d/*-test.sh` | `./test/shell` | Manifest discovery, CLI behavior with fake homes and stub binaries, shell registry behavior, static QML invariants, pure JavaScript models, lifecycle transactions, and local negative cases |
| Current non-graphical aggregate | `test/all` | `./test/all` | Regression gate for CLI and shell changes only; it must not be cited as native or graphical proof |
| Compositor-gated shell smoke | A focused `test/shell.d/<area>-test.sh` using `require_compositor` | `bash test/shell.d/<area>-test.sh` or `./test/shell` | Development smoke tests that need a reachable Wayland socket; keep static assertions in the same file runnable before the compositor gate |

New shell suites source `test/shell.d/base-test.sh`. Tests use a temporary `HOME`, set `OMARCHY_PATH="$ROOT"`, stub external commands, and assert invariants rather than whole-file snapshots. Plain model logic should remain in importable JavaScript and run through `run_node_test` where possible.

### Native Qt unit and integration tests

`B0` should make CTest the authoritative native entry point and provide CMake presets or equivalent documented configure options. Until the production tree exists, the exact contract is:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/plugin-runtime
ctest --test-dir build/plugin-runtime --output-on-failure
```

CTest labels should make security gates independently runnable:

```bash
ctest --test-dir build/plugin-runtime -L unit --output-on-failure
ctest --test-dir build/plugin-runtime -L protocol --output-on-failure
ctest --test-dir build/plugin-runtime -L adversarial --output-on-failure
ctest --test-dir build/plugin-runtime -L property --output-on-failure
ctest --test-dir build/plugin-runtime -L integration --output-on-failure
```

Qt tests that only instantiate QML or render offscreen run with `QT_QPA_PLATFORM=offscreen`, `QT_QPA_PLATFORMTHEME=none`, `QSG_RHI_BACKEND=software`, and `QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0`; render-worker tests also select `QSGRendererInterface::Software` programmatically before creating the Qt Quick window. Tests requiring the real Quickshell import path, layer-shell behavior, Hyprland input, or multiple outputs belong in acceptance, not in headless CTest.

The production PKGBUILD's `check()` function must configure with `BUILD_TESTING=ON` and run the complete bounded CTest suite. Persistent fuzzing and performance thresholds do not belong in `check()`.

### Graphical acceptance in a disposable VM

Installed graphical tests live in `test/acceptance.d/*-test.sh`, source `test/acceptance.d/base-test.sh`, and run through `test/acceptance`. They must be driven by the sibling `omarchy-iso` repository because the suite opens applications, changes session state, and exercises the real compositor.

For acceptance-test-only changes, reuse an installed VM base and synchronize only the suite:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-test release/<iso>.iso --reuse-base --sync-omarchy ../omarchy --no-preview
```

When local `bin/`, `config/`, or `shell/` source must be copied into the installed base, use:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-test release/<iso>.iso --reuse-base --sync-all ../omarchy --no-preview
```

Neither reuse command proves that a newly compiled native artifact or changed package dependency installs correctly. Native targets, package manifests, installation paths, services, finalization, or shipped-default changes require a fresh ISO from both local repositories:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

Secure plugin acceptance should be split into focused files such as `plugin-security-lifecycle-test.sh`, `plugin-security-bar-test.sh`, `plugin-security-overlay-test.sh`, and `plugin-security-denial-test.sh`. Each file must restore modified state with traps, stop its workers, capture every visually distinct success state, and leave failure screenshots and logs in `$OMARCHY_ACCEPTANCE_DIR`.

The current workspace has no sibling `omarchy-iso` checkout, so VM commands cannot run here until that repository is present. This is an environment dependency for `F2`, `F4`, and `F5`, not a design blocker for earlier nodes.

### Packaging through `omarchy-pkgs`

The native host, worker, protocol library, and trusted QML bridge must be built and upgraded atomically. Per `A1`, the final dependency declarations and PKGBUILD integration belong in the sibling `omarchy-pkgs` repository. The package build entry point there is:

```bash
cd ../omarchy-pkgs
./bin/build --mirror edge --package omarchy
```

The current sibling checkout does not contain a `pkgbuilds/*/omarchy/` or `pkgbuilds/*/omarchy-dev/` recipe, so that exact build is not runnable yet. `B0` must resolve whether the source package recipe is generated elsewhere or add the authoritative recipe before claiming packaging completion. A local experimental `makepkg` proves PKGBUILD mechanics but does not replace the repository build or fresh-ISO install proof.

The package gate must inspect archive paths and ELF dependencies, run the PKGBUILD `check()` CTest suite, install into a fresh ISO, verify the trusted QML module is importable by packaged Quickshell, and verify the worker is private libexec rather than an ordinary command on `PATH`.

### Adversarial tests

Deterministic malicious peers belong in native CTest with the `adversarial` label and shared fixtures owned by `B6`/`C11`. They cover exact 40-byte golden parsing, envelope-version and role-version negotiation, packets at and one byte above the 4 KiB, 64 KiB, and 16 KiB endpoint caps, endpoint-role swaps, forged identity fields, strict daemon-side outer PID/UID/GID plus pidfd matching, legitimate worker-observed PID-zero translation and inconsistent `SO_PEERCRED` baselines, invalid message order, correlation reuse and cancellation races, stale launch generations and handles, revoked grants, broker disappearance, worker crashes, and denial of filesystem, network, D-Bus, Wayland, agent sockets, and cross-plugin state. Descriptor-injection cases compare the trusted process's open-FD set before and after every fatal path and prove that unexpected, malformed, excess, and schema-rejected descriptors are closed before any error response or endpoint teardown.

Tests must assert the denied operation and the surviving trusted process, not merely a nonzero worker exit. Sandbox escape probes that could touch the developer session run only against synthetic paths in a temporary directory. Final attacks involving the installed service manager, real user bus, compositor socket, cgroups, or package permissions run in the disposable VM.

### Fuzz and property tests

There is no fuzzing framework in the repository today. `B6` should add native parser harnesses using Clang libFuzzer for the outer envelope, manifest, capability schema, broker messages, render messages, and audit redaction. Fuzzer targets build only when `PLUGIN_SECURITY_BUILD_FUZZERS=ON`:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime-fuzz -G Ninja -DPLUGIN_SECURITY_BUILD_FUZZERS=ON -DCMAKE_CXX_COMPILER=clang++
cmake --build build/plugin-runtime-fuzz --target plugin-security-fuzzers
```

Seed corpora and regression inputs live under `test/plugin-security/fuzz/<target>/`; every crashing input becomes a deterministic CTest regression. Bounded property tests use deterministic printed seeds, run under the CTest `property` label, and cover encode/decode round trips, grant monotonicity, revision-state transitions, path normalization, bounds arithmetic, cancellation, and redaction. A longer fuzz campaign is a release artifact, not part of `./test/all` or PKGBUILD `check()`.

### Benchmarks

There is no native or rendering benchmark harness today. `B6` should provide a native benchmark executable whose machine-readable output lands under `build/plugin-runtime/results/`. Benchmarks must report distributions rather than one timing and include fixture version, Qt version, renderer, resolution, DPR, monitor count, CPU, and GPU/software backend.

Required cases are frame production, frame copy/presentation, input round trip, broker request latency, startup time, steady-state memory, crash recovery, rate-limit behavior, and 1/10/60-second frame pacing. Run correctness separately before measurement. Performance tests should record baselines and budgets at `G0`/`B4`; unstable developer-machine timings inform design but do not gate merges. Reproducible release measurements for `F2` run inside a pinned disposable VM, with GPU results kept separate from software-render results.

The existing `omarchy dev benchmark cli` command measures only CLI routing and is not suitable for plugin runtime measurements.

### Visual verification

Every visual change requires inspection in addition to automation. For a locally running development shell, capture reference and candidate screenshots with:

```bash
omarchy capture screenshot fullscreen save
```

For animation, transition, frame pacing, pet motion, slide-outs, or input latency, record and inspect a short video:

```bash
omarchy screenrecord --fullscreen
omarchy screenrecord --stop-recording
```

Acceptance tests use their `screenshot "success-<step>"` helper, plus `layer_present`, `layer_on_screen`, `window_present`, `screen_contains`, Hyprland JSON, and `wtype` for deterministic interaction. Visual inspection must check clipping, incorrect alpha, stale frames, scaling, focus, z-order, spoofable identity chrome, and cleanup after crash/revoke. QMP virtual keyboard input in `omarchy-iso` is required to prove compositor-level shortcuts; in-guest `wtype` does not prove global keybindings.

## Node-to-test-layer matrix

The matrix names the minimum required layers. `N` is native CTest, `C` is `test/cli`, `S` is `test/shell`, `A` is disposable-VM acceptance, `P` is `omarchy-pkgs` plus a fresh ISO, `X` is adversarial, `F` is fuzz/property, `M` is benchmark, and `V` is inspected visual evidence.

| Node | Required layers | Exit evidence |
| --- | --- | --- |
| `R0` | evidence audit | Research sources, threat assumptions, and representative migration corpus remain traceable and current |
| `A0` | review | Every authority and channel is mapped to an owning process and negative invariant |
| `A1` | N, P-spike | CMake/CTest build, QML load, staged package contents, ELF dependency inspection |
| `A2` | N, X | Framing round trip, bounds rejection, kernel credential check, payload identity forgery denial |
| `A3` | N, S, M, V | Animated producer/consumer, measured transport, Quickshell import/load result, inspected pixels |
| `A4` | review | This survey and confirmed repository/tool availability |
| `B0` | N, P | Installed paths, version output, private worker invocation denial, PKGBUILD `check()` |
| `B1` | N, S, F | Golden manifests, capability fingerprints, complete revision-state transition properties |
| `B2` | N, C, S, F | Grant schema, CLI errors, scope and revocation properties, redaction vectors |
| `B3` | N, X, F | Golden wire messages, negotiation, order/bounds/cancellation failures, parser fuzz target |
| `B4` | N, X, F, M | Golden render/input messages, bounds arithmetic properties, invalid-surface vectors, baseline budgets |
| `B5` | N, X | Namespace/mount/env/fd/cgroup policy vectors and expected-denial certificates |
| `B6` | N, X, F, M | Fake peers, reusable malicious probes, seed corpora, deterministic benchmark fixtures |
| `B7` | S, F | Stable inventory taxonomy, synthetic findings, false-positive and worksheet fixtures |
| `C0` | N, S, F | Valid/invalid discovery corpus, path and canonicalization properties |
| `C1` | N, S, X, F | Atomic stage/activate/rollback tests, fault injection, state-machine properties |
| `C2` | N, C, S, X, F | Grant mutations, concurrent/revoked state, fail-closed CLI and store behavior |
| `C3` | N, C, S, F | Append/query/redaction tests and redaction property corpus |
| `C4` | N, X, F | Authenticated dispatch, forged identity denial, malformed and unavailable-peer behavior |
| `C5` | N, X, M | Offscreen QML render, forbidden API probes, frame/resource bounds, startup/render cost |
| `C6` | N, S, X | Fake frame producer, bounded consumption and input, disconnect and invalid-frame cleanup |
| `C7` | N, S, X | Bubblewrap command construction, real sandbox denial probes, teardown and orphan cleanup |
| `C8` | N, X, F | Provider operation/scope/handle vectors, revoked and malformed request denial |
| `C9` | S, F | Pinned and synthetic inventory outputs, deterministic report normalization |
| `C10` | N, S | Fixture QML loads against SDK fakes without ambient host services |
| `C11` | N, X, F | Malicious worker suite, expected-denial assertions, minimized regression corpus |
| `D0` | N, C, S, X | Staged revision and permission integration, stale/forged revision failures |
| `D1` | N, X | Real launcher/channel/broker pair, credential substitution and peer-loss teardown |
| `D2` | N, X, M | Worker/transport/bridge loop, oversized/stale frames, throughput and latency |
| `D3` | N, S, A, X, V | Surface/input/focus policy, invalid surface denial, inspector and identity chrome |
| `D4` | N, C, S, X, F | Grant lookup/provider/audit trace, stale handles and revoked request denial |
| `D5` | N, X, M | Limits, crash loops, restart storms, stale-channel cleanup, recovery timings |
| `D6` | S | Deterministic report/worksheet generation against representative fixtures |
| `E0` | N, X | End-to-end no-authority worker and clean termination trace |
| `E1` | N, A, X, M, V | Animated arbitrary-QML bar, bounded input/state, denial trace, latency and screenshots/video |
| `E2` | N, A, X, M, V | Alpha/pet/slide-out, irregular input, host-owned placement/z-order/limits, screenshots/video |
| `E3` | N, A, X, V | Fake service UI, declared operations only, gesture/scope denials, visible identity |
| `E4` | N, C, S, A, X | Permission-delta staging, atomic activation, immediate worker/handle revocation |
| `E5` | C, S, A, X | Honest schema-v1 labeling, indivisible consent, update hardening and rollback |
| `F0` | X, A | Installed filesystem/network/D-Bus/Wayland/socket/cross-plugin/confused-deputy attack report |
| `F1` | N, X, F, M | Malformed corpus, sustained-rate/exhaustion results, crash/restart budget evidence |
| `F2` | A, M, V | Pinned-VM latency/pacing/cost/DPR/multi-monitor results and inspected visual artifacts |
| `F3` | N, C, S, A, X | Full lifecycle/recovery matrix across process, broker, shell, and machine restarts |
| `F4` | A, V | Recorded permission/inspection flows, wording review, spoof-resistance and audit comprehension findings |
| `F5` | P, A | Clean repository package build, fresh ISO install, full installed acceptance logs and artifacts |
| `F6` | N, S, A, V | Three corpus migrations, generated worksheets, working local widget/overlay/service evidence |
| `G0`–`G3` | aggregate listed parents | Per-parent evidence can pass independently; failed descendants remain stopped |
| `G4` | N, C, S, A, P, X, F, M, V | One release candidate passes all bounded suites and has reviewed long-run evidence |
| `Z0`, `Z1`, `Z2` | evidence audit | Discussion, reference PR, and follow-on backlog link immutable gate evidence and state unsupported behaviors explicitly |

## Repository dependency summary

| Work | `omarchy` only | Requires `omarchy-pkgs` | Requires `omarchy-iso` |
| --- | --- | --- | --- |
| Contracts, native unit tests, shell/CLI tests, local adversarial tests, fuzzing, headless rendering | Yes | No | No |
| Native package recipe, dependencies, installed paths, PKGBUILD `check()`, archive/ELF inspection | No | Yes | No |
| Acceptance-only test edits against a suitable existing installed build | Test source is here | No | Yes, with `--reuse-base --sync-omarchy` |
| Local shell/bin/config acceptance against a suitable installed native runtime | Source is here | No | Yes, with `--reuse-base --sync-all` |
| New native binaries/QML module, changed package dependencies, services, install/finalization, shipped defaults | Source is here | Yes | Yes, fresh ISO with both local sources |
| Compositor input, layer-shell policy, multi-monitor/DPR, visual permission UX, crash/restart behavior in an installed session | Source is here | Only if package changed | Yes |

## Gate policy

- `G0` must freeze the native test directory, CTest labels, fixture locations, benchmark output schema, and which package recipe owns native installation.
- `G1` requires focused isolated tests and golden vectors; it does not require a VM for nonvisual components.
- `G2` requires negative pairwise tests, including teardown and peer incompatibility.
- `G3` requires working end-to-end fixtures; visual slices add acceptance artifacts, while `E0` may remain headless.
- `G4` requires one fresh ISO built from the exact candidate `omarchy` and `omarchy-pkgs` revisions, the bounded suites, a recorded long-running fuzz campaign, reproducible benchmarks, and inspected visual artifacts.
- Unsupported behavior remains denied when its proof layer is absent. A local screenshot, a happy-path CTest, or `./test/all` cannot substitute for an installed boundary proof.
