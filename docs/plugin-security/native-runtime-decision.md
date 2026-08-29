# Native plugin runtime decision record

Status: provisional reference implementation; measurements taken on 2026-08-28 from commit `ad07ab165ef1e7a16e0a4d870212b8376d6d7d96` with a dirty-tree fingerprint recorded by the live-lab staging helper. Repeat the measurements on the reviewed clean candidate before quoting them in a PR.

## Why native code is proposed

The security boundary needs operations Bash and QML cannot implement safely: inherited `SOCK_SEQPACKET` channels with peer credentials and descriptor quarantine, pidfds, exact descriptor inheritance, seccomp filters, namespace launch, cgroup supervision, bounded binary codecs, shared-memory frame transport, and a Qt Quick renderer outside the trusted shell. QML remains the plugin language; native code owns only the isolation, authorization, lifecycle and rendering boundary.

This is not free. Omarchy is mostly Bash and QML, while the current reference runtime is large enough to demand its own ownership and release discipline. The correct comparison is not “C++ is faster.” It is whether a smaller implementation can preserve arbitrary QML and the same enforceable boundary.

## Measured cost

The following commands provide reproducible measurements:

```bash
find native/plugin-runtime -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) ! -path '*/tests/*' ! -name '*_test.cpp' ! -name '*test.cpp' -print0 | xargs -0 wc -l
find native/plugin-runtime -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) -print0 | xargs -0 wc -l
cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-runtime-metrics -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
time cmake --build /tmp/omarchy-plugin-runtime-metrics -j16
native/plugin-runtime/lab/omarchy-plugin-security-lab prepare /tmp/omarchy-plugin-runtime-metrics /tmp/omarchy-plugin-security-stage
find /tmp/omarchy-plugin-security-stage/<digest>/usr -type f -printf '%s %p\n' | sort -nr
readelf -d /tmp/omarchy-plugin-security-stage/<digest>/usr/bin/omarchy-plugin-host
```

On this 16-thread Omarchy 4.0.1 host:

| Measure | Observed value |
| --- | ---: |
| C/C++ lines excluding conventional test paths/names | 24,600 |
| All C/C++ lines | 41,847 |
| Test/fixture/proof heuristic, with some overlap | 18,756 |
| Clean Release configure, tests disabled | 0.786 seconds |
| Clean Release build with 16 jobs, tests disabled | 13.304 seconds |
| Installed `/usr` payload | 2.5 MiB |
| Host executable | 1,124,264 bytes |
| Worker executable | 550,920 bytes |
| Permission CLI | 456,432 bytes |
| Audit CLI | 330,624 bytes |
| QML bridge module | 136,088 bytes plus 3,894 bytes metadata |

The `BUILD_TESTING=OFF` build still compiled `omarchy-plugin-capability-definition-test`; that target should be put behind the test guard. It did not install, but compiling tests in a production package wastes time and obscures the product boundary.

The host directly links Qt 6 Core, Gui, Qml, Quick, Network and OpenGL, plus libseccomp, libsystemd, libstdc++, libc, libm, libgcc, GLX and OpenGL. The worker links the same Qt stack and libseccomp but not libsystemd. The QML bridge links the Qt stack. Bubblewrap is an exec-time dependency, and the current live providers add fixed executable dependencies such as the Omarchy notification helper and `pw-play`. Package metadata must declare the direct dependencies and treat the Qt, graphics-driver, Bubblewrap, systemd and kernel namespace/seccomp surfaces as runtime assumptions.

## Trusted computing base partition

The current source should be reviewed as separate trust zones even though static linking folds much of it into the host binary:

| Partition | Security role | Approximate C/C++ lines by directory | Ships |
| --- | --- | ---: | --- |
| Manifest, wire, permission, capability, sandbox and surface contracts | Parse and bound attacker-controlled formats; define authority | 10,334 | Linked into host/worker as needed |
| Launcher, authenticated channels and health | Kernel/process boundary and teardown | 4,986 | Host |
| Broker core, audited runtime and providers | Authorization immediately before effects | 4,457 | Host |
| Grants, audit, revision, discovery, lifecycle and update | Durable identity and authority state | 8,893 | Host and two CLIs |
| Worker runtime and sidecars | Executes hostile QML inside confinement | 3,809 | Worker; not trusted for confidentiality or integrity outside sandbox |
| Render session, surface host, bridge and trusted bridge | Validates frames/input and presents into shell-owned surfaces | 2,862 | Host and QML bridge |
| Product composition and host CLI | Wires trusted pieces and feature gates | 937 | Host |

Directory totals overlap the broad line-count categories only conceptually, not by file. Generated Qt code and third-party libraries are excluded. The worker is security-sensitive because parser bugs affect availability and sandbox attack surface, but it must not be trusted with ambient user authority. Provider adapters are high-risk TCB and should be split into separate processes where their parser or credential surface warrants it.

Reference-only and test-only code does not need to ship: `fixtures/`, `tests/`, `proof-campaigns/`, `proof-exhaustion/`, `render-proof/`, `brokered-action/`, `vertical-slices/`, test support, fake providers, malicious peers, fuzz corpora and product fixtures. `migration-report` is an authoring/review tool and is currently built but not installed; it should remain outside the runtime package or become a separate optional tool. `expressive-surface` is a proof component and is not installed. Static libraries should remain build artifacts rather than public packages.

## Public ABI and protocol surface

There is no supported public C++ shared-library ABI. The intended shell-facing QML ABI is one module, `Omarchy.PluginHost`, with two types: `PluginHostInfo 1.0` and `RemotePluginSurface 1.0`. Their QML properties and signals are the public surface. Worker, control, render and broker envelopes are private versioned protocols and must negotiate exact versions; they are not plugin APIs.

The bridge currently exports many C++ symbols because default ELF visibility is used. That is accidental ABI surface. A production build should use hidden visibility and export only Qt's plugin entry points, then freeze and test the QML type metadata. The CLI syntax and stored grant/audit formats are versioned operational interfaces and require compatibility policy even though they are not language ABIs.

## Alternatives

| Approach | What it buys | What it loses or still needs | Decision |
| --- | --- | --- | --- |
| Current C++/Qt host and worker | Reuses Qt Quick for arbitrary QML, gives direct control over FDs, pidfds, seccomp, shared memory and QML embedding | Largest new maintenance and memory/Qt attack surface; C++ memory safety; currently oversized reference tree | Viable reference, but reduce and partition before production |
| Minimal native launcher/bridge plus portals | Much smaller privileged core; mature desktop consent for files, URIs, screenshots and some devices | Portals do not cover arbitrary account APIs, constrained CLIs, plugin-private broker semantics, render transport or lifecycle; a Qt worker is still required for arbitrary QML | Preferred direction for capabilities portals already model; not a complete replacement |
| Rust supervisor/broker with a thin C++ Qt bridge and Qt worker | Memory-safe parsing/state/lifecycle and strong typed protocols; isolates unavoidable Qt code | Adds Rust toolchain and FFI boundary; Qt/QML worker and bridge remain C++; rewrite cost and less existing Omarchy expertise | Strong production candidate after the protocol stabilizes; benchmark maintenance and package cost with a vertical slice |
| Bash/systemd proxies | Fits repository skills; systemd supplies scopes and service lifecycle | Shell cannot safely parse hostile binary protocols, quarantine descriptors, maintain asynchronous correlation state, or implement shared-memory rendering; command quoting is the wrong authority boundary | Suitable orchestration around a native core, not the broker or protocol parser |
| Trusted-only in-process QML status quo | Minimal implementation and perfect compatibility | No meaningful sandbox or granular permission claim; plugin has the user's shell authority and crash fate | Retain only as explicitly unsafe/trusted extension mode |

The smallest credible production architecture is likely: Bubblewrap/systemd for kernel isolation, a memory-safe broker/supervisor, a narrowly exported C++ Qt bridge, a disposable Qt QML worker, and portals or separately sandboxed providers wherever available. The current all-C++ tree proves contracts and integration but should not automatically become the permanent package boundary.

## Release conditions

Before enabling this runtime by default:

- separate installed production targets from reference/test targets and stop compiling tests under `BUILD_TESTING=OFF`;
- publish clean-candidate LOC, build-time, binary-size and dependency measurements in CI;
- hide accidental bridge symbols and freeze the QML/protocol/storage compatibility surfaces;
- assign maintainers for the launcher/channel, broker/grants, Qt worker/render and provider partitions;
- run sanitizers, fuzz/property tests, malicious-peer tests and disposable-VM acceptance for every supported Qt/kernel baseline;
- compare a Rust broker/supervisor vertical slice and portal-backed providers against the current implementation using code size, auditability, package cost and behavior—not language preference;
- keep schema-v1 behavior explicitly trusted-only until users choose migration.
