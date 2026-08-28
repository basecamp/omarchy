# B5 sandbox and resource policy

## Result

B5 freezes a deny-by-default worker launch policy in `native/plugin-runtime/contracts/sandbox`. Policy construction is a pure library: it returns Bubblewrap arguments, the complete environment, descriptor sets, seccomp syscall sets, transient-scope properties, ceilings, deadlines, and teardown ordering. It never forks, opens a plugin path, creates a cgroup, or grants authority. The later `C7` launcher owns those operations and must consume this contract without accepting worker-selected policy fields.

The contract builds on the hardened G0 launch sequence: `/usr/bin/bwrap` is pinned; the supervisor normalizes standard streams, collision-safely relocates descriptors, closes everything outside its allowlist, obtains Bubblewrap's reported outer worker PID, opens a pidfd, and releases the startup barrier only after binding the launch record. B5 does not reimplement the G0 JSON-status parser or add its spike-only json-c dependency.

## Process and namespace policy

Every QML worker gets new user, PID, mount, IPC, UTS, network, and cgroup namespaces. Bubblewrap must successfully apply `--disable-userns` and `--assert-userns-disabled`; production uses `--unshare-cgroup`, not the best-effort form. The worker is PID 1, receives UID/GID 0 only inside its private user namespace, starts a new session, loses all capabilities, and dies with its parent. The fixed hostname is `omarchy-plugin`.

The initial model permits threads but not child processes. The seccomp clone rule requires `CLONE_VM | CLONE_SIGHAND | CLONE_THREAD` and rejects every namespace flag plus `CLONE_VFORK`; `clone3` is denied because seccomp cannot inspect its pointed-to argument structure. Helpers must be separate supervised workers with fresh generations and channels.

No untrusted QML is evaluated until the worker installs the steady-state filter. Bubblewrap's launch filter necessarily allows the one `execve`/`execveat` that starts the trusted worker. The steady-state filter removes both calls, so plugin files and library-side helper executables cannot be executed after QML becomes active. Both filters default to `EPERM`; `clone3` has an explicit `ENOSYS` denial so current libc falls back to the inspectable restricted `clone` rule instead of making Qt threads unusable. Only the syscall names in `policy.cpp` are admitted, with the restricted clone rule replacing an unconditional clone allow. In particular, socket creation, namespace creation, ptrace, mount, BPF, keyrings, perf events, io_uring setup, userfaultfd, reboot, swap operations, and handle-based opens are absent. `C5` owns installing and verifying the second filter before it parses the plugin entry point.

## Filesystem policy

The sandbox starts from an empty synthetic root. It does not bind the host root, full `/usr`, `/bin`, `/sbin`, `/etc`, `/home`, `/run/user`, `/sys`, or a host `/dev`.

| Sandbox path | Source and mode | Purpose |
|---|---|---|
| `/runtime/worker` | Installed private worker path, read-only bind | The only initial executable. `/runtime` is the complete worker `PATH`. |
| `/usr/lib` | Host root-owned library tree, read-only bind | Dynamic loader, Qt, C/C++ runtime, plugins, and library data. `/lib` and `/lib64` are synthetic symlinks to it. |
| `/usr/share/fonts`, `/usr/share/fontconfig`, `/etc/fonts` | Read-only bind if present | Software-rendering font discovery only. |
| `/etc/ld.so.cache`, `/etc/localtime` | Read-only bind if present | Loader resolution and deterministic local-time behavior without the rest of `/etc`. |
| `/plugin` | Supervisor-opened revision directory FD 9, read-only bind | Immutable activated content. No plugin-selected host path is resolved during launch. |
| `/state` | Supervisor-opened plugin-private state directory FD 10, read-write bind | State already isolated by canonical plugin identity and revision policy. It is never another plugin's directory or the real home. |
| `/tmp` | New 64 MiB tmpfs | Per-generation scratch; removed at teardown. |
| `/run` | New 16 MiB tmpfs; `/run/plugin` mode 0700 | Private runtime files. It contains no user bus, Wayland socket, PipeWire socket, credential socket, or agent. |
| `/home` | New tmpfs; `/home/plugin` mode 0700 | Empty private home namespace. |
| `/proc` | New procfs in the PID namespace | Self/process runtime information; host processes are invisible. |
| `/dev` | Bubblewrap-created minimal synthetic device tree | Standard pseudo-devices only. No DRI, input, camera, sound, USB, block, TPM, or other host device is bound. |

The read-write `/state` mount is private storage, not ambient file authority. User-selected files, downloads, credentials, configuration outside the plugin state root, and other scoped resources stay behind broker operations and opaque handles. Future worker types that do not receive persistent private storage use a separate plan variant rather than substituting a worker-provided path.

## Environment and descriptor policy

The pre-Bubblewrap environment is exactly `PATH=/usr/bin` and `PWD=/`. Bubblewrap clears it before constructing the worker environment:

```text
HOME=/home/plugin
LANG=C.UTF-8
LC_ALL=C.UTF-8
PATH=/runtime
PWD=/plugin
QT_QPA_PLATFORM=offscreen
QSG_RHI_BACKEND=software
XDG_CACHE_HOME=/tmp/cache
XDG_CONFIG_HOME=/state/config
XDG_DATA_HOME=/state/data
XDG_RUNTIME_DIR=/run/plugin
```

The manager never forwards `DISPLAY`, `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS`, `SSH_AUTH_SOCK`, `GNUPGHOME`, `XAUTHORITY`, Qt overrides, locale overrides, proxy variables, credential variables, or its general systemd environment. Programmatic `QQuickWindow::setGraphicsApi(QSGRendererInterface::Software)` remains required in `C5`; the environment is a second fixed input, not the only enforcement.

FD 0 is normalized to `/dev/null`. FD 1 and FD 2 are supervisor-owned bounded capture pipes. FD 3 is control, FD 4 is broker RPC, and FD 5 is render/input. Those are the only nonstandard descriptors visible at worker entry and are marked close-on-exec before plugin code. Bubblewrap consumes FD 6 status, FD 7 barrier, FD 8 seccomp BPF, FD 9 revision, and FD 10 private state during setup. Everything else is closed before `execve`.

Later typed frame-memory descriptors are delivered only on FD 5 after the B3/B4 envelope, role, generation, credential, pidfd-lifetime, descriptor-count, size, seal, and ownership checks pass. They are not ambient launch descriptors. FD 3 never accepts descriptors; FD 4 defaults to none and gains a descriptor only through a separately frozen broker message contract.

## Resource and recovery ceilings

Each generation runs in its own transient user scope named from trusted data with prefix `app-omarchy-plugin-worker-`. The trusted supervisor applies these properties before releasing the startup barrier:

| Control | Ceiling |
|---|---:|
| `MemoryHigh` | 384 MiB |
| `MemoryMax` | 512 MiB |
| `TasksMax` | 16 |
| `CPUQuota` | 50% of one CPU |
| `CPUWeight` | 20 |
| `IOWeight` | 10 |
| `LimitNOFILE` | 64 |
| `LimitFSIZE` | 64 MiB |
| `LimitCORE` | 0 |
| `OOMPolicy` | `kill` |
| `KillMode` | `control-group` |
| Captured output burst | 64 KiB per generation |
| Sustained captured output | 4 KiB/s per generation |

Launch has five seconds to produce a usable Bubblewrap status and pidfd binding, followed by three seconds for the control-channel hello. A broker request defaults to 30 seconds unless its operation contract is tighter. Graceful shutdown gets one second; forced pidfd/cgroup teardown gets two seconds. At most three worker crashes in 60 seconds are restarted, with exponential backoff from one to 30 seconds; five stable minutes reset the burst window. The graphical-session host service itself is limited to five restarts in 60 seconds, in addition to its five-second `RestartSec`. A limit violation invalidates the generation before any restart. `C7` must apply the host `StartLimitIntervalSec`/`StartLimitBurst` values when it turns the B0 inert unit into an active supervisor.

The teardown order is fixed: stop accepting messages, invalidate generation-bound handles, request graceful shutdown, send `SIGKILL` through retained pidfds on deadline, kill the complete generation cgroup, reap only with bounded `WNOHANG` polling, then remove runtime and scratch state. Every receive polls the pidfd beside its endpoint and rechecks it after `recvmsg`; any pidfd state other than exactly alive is fatal. A recycled numeric PID is never a teardown target.

The graphical-session-scoped host may run without Quickshell. Shell absence closes or withholds presentation channels but does not give a worker a compositor connection. Bridge reconnection creates a new trusted daemon-to-bridge binding; it never reuses a worker-created endpoint. Session stop tears down every generation through the host service and the per-generation cgroups.

## Executable evidence

`plugin-sandbox-policy` exhaustively asserts the argument, mount, environment, descriptor, resource, timeout, restart, pidfd, cgroup, capability, and two-stage seccomp contract. The production builder has no worker-path or descriptor override: it always selects the installed private worker and fixed ABI. A visibly test-only builder accepts an alternate absolute, lexically normalized worker path for the synthetic probe and rejects relative or noncanonical paths.

`plugin-sandbox-enforcement` is a synthetic-resource probe. It creates temporary revision and state directories, builds the real policy, exports the launch filter with libseccomp, and enters Bubblewrap through the fixed descriptor ABI. Inside the sandbox it proves the exact environment and FD set, PID/UID/GID and hostname, read-only revision, writable private state and scratch, zero capabilities, denied network socket and nested user namespace, and absence of a synthetic host secret, user bus, shell, GPU, and input device. The outer managed command sandbox blocks Bubblewrap's netlink/user-namespace setup; the unchanged test passes through the approved ordinary-host test path. libseccomp is a test/compiler dependency here, not a json-c replacement or a parser dependency.

The local proof does not establish systemd-user cgroup enforcement because the managed test context cannot reach the user manager. It also does not claim installed Qt worker startup, steady-state filter installation, resource exhaustion behavior, crash-loop recovery, session teardown, real compositor/bus/agent denial, hostile device nodes, multi-user boundaries, or behavior across Omarchy's supported kernels. Those are disposable-VM tests owned by `C5`, `C7`, `D1`, `D5`, `F0`, `F1`, `F3`, and `F5`. A policy vector is not enforcement until those layers pass.
