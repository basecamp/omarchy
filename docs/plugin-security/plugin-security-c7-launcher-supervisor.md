# C7 Bubblewrap launcher and pidfd supervisor

Status: implementation complete in isolation; D1 still owns host lifecycle and broker integration.

## Production boundary

`native/plugin-runtime/launcher` turns the B5 pure policy into a process without accepting a worker-selected executable, Bubblewrap option, environment value, mount path, identity, descriptor number, seccomp rule, or resource ceiling. `Supervisor::production()` pins `/usr/bin/bwrap`, `/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker`, the B5 plan, and the systemd user-scope controller. Both executables must be absolute, normalized, regular, executable, root-owned, non-set-ID, and not group- or world-writable. The only override is named `forTestOnly` and is used by synthetic test executables; it is not called by the installed host.

The trusted request contains a canonical B1 plugin identifier, lowercase SHA-256 revision, nonzero generation, and already-open revision/state directory descriptors. C7 duplicates and validates those descriptors rather than resolving plugin-supplied paths. The revision must be user-owned, private against group/other writers, and have no write mode bit; the state directory must be user-owned and private against group/other writers. C1 remains the authority that creates, pins, and activates the immutable revision.

The launcher is an internal static module linked into the already-installed `omarchy-plugin-host`, not a second installed command that a plugin can invoke. `omarchy-plugin-host --check-launch-prerequisites` exposes a fail-closed administrator/package check without launching a worker. D1 will connect activation records, broker endpoints, and the host event loop to this module.

## Launch sequence

Before creating a channel or pipe, C7 normalizes any closed standard descriptor to `/dev/null`. It verifies `pidfd_open`, strict pidfd polling, and `close_range`, then compiles the B5 launch seccomp policy into a sealed memfd. It creates three distinct `SOCK_SEQPACKET | SOCK_CLOEXEC` pairs with trusted-side `SO_PASSCRED`, bounded standard-output/error pipes, Bubblewrap status and startup-barrier pipes, and a close-on-exec error pipe.

After `fork`, the child stages every descriptor above the reserved range before assigning destinations, so an occupied destination cannot overwrite a later source. It installs standard streams at FD 0 through 2, control/broker/render at FD 3 through 5, Bubblewrap status/barrier/seccomp/revision/state at FD 6 through 10, and the exec-error handshake at FD 11. It closes everything at FD 12 and above, applies B5 `RLIMIT_NOFILE`, `RLIMIT_FSIZE`, and `RLIMIT_CORE`, sets `PR_SET_NO_NEW_PRIVS`, marks only the error handshake close-on-exec, and calls `execve` on the trusted Bubblewrap path with exactly B5's two-entry pre-Bubblewrap environment. There is no shell or `PATH` lookup.

The parent installs a direct-child cleanup guard immediately after `fork`. A monitor pidfd is preferred; the exceptional pre-pidfd path uses the still-unreaped direct-child identity, `SIGKILL`, bounded `waitpid(WNOHANG)` retries, and no blocking wait. A successful `execve` closes the error pipe. An `execve` failure returns its captured `errno`, which is distinguished from malformed status, early worker exit, and timeout.

Bubblewrap status is read as at most 32 JSON Lines of at most 4 KiB each under B5's five-second deadline. Qt's JSON parser handles unknown objects and members. A separate top-level key scan decodes escaped JSON keys before rejecting duplicate `child-pid` or `exit-code` authorities. Both fields must be exact bounded integers. C7 opens the reported outer worker pidfd, requires it to be exactly alive, and never infers worker identity from the monitor PID or numeric adjacency.

## Resource barrier

Before releasing Bubblewrap's startup barrier, C7 asks the systemd user manager to create a collision-resistant per-generation `.scope` whose trusted name includes the canonical identity, generation, and fresh monitor PID. It attaches both the Bubblewrap monitor and reported outer worker and applies B5 `MemoryHigh`, `MemoryMax`, `TasksMax`, `CPUQuota`, `CPUWeight`, and `IOWeight`. C7 then waits under the launch deadline until `/proc/<worker>/cgroup` proves the worker has migrated into that exact scope. A queued systemd job is not treated as enforcement. Failure or timeout kills/removes any partially created scope and aborts the launch.

The B5 `LimitNOFILE`, `LimitFSIZE`, and `LimitCORE` strings cannot be properties of a transient `.scope`; systemd correctly rejects them there because rlimits must exist before the process executes. C7 therefore realizes those same frozen values with `setrlimit` in the trusted child before Bubblewrap. The real probe verifies all three values and `NoNewPrivs=1` inside the worker. `OOMPolicy` and `KillMode` are service semantics rather than valid scope properties; C7 explicitly kills the whole scope on forced teardown, while the kernel `MemoryMax` limit remains the worker memory enforcement. D5 owns crash classification and restart policy.

Only after cgroup placement and a second exactly-alive pidfd check does C7 close the barrier. The worker then starts as PID 1 and UID/GID 0 inside its private namespace while the trusted endpoint binding records Bubblewrap's outer PID, the host UID/GID, canonical plugin ID, revision, and generation.

## Receive and teardown

Every receive selects its endpoint from a trusted `EndpointRole`, polls that socket beside the retained worker pidfd, rejects exit or any unusable pidfd event, uses kernel `SCM_CREDENTIALS`, quarantines and closes every received descriptor, rejects worker-originated descriptors, verifies the exact outer PID/UID/GID tuple, and rechecks pidfd liveness after `recvmsg`. A payload claim never chooses an endpoint or identity. Unknown role enum values fail before polling.

Teardown first disables receives and closes all three channels. It waits only B5's graceful interval, signals through the worker pidfd on timeout, kills the complete systemd scope, bounds the forced wait, signals and reaps the direct Bubblewrap monitor through its pidfd, and removes the scope. Linux may report a retained pidfd as `POLLIN|POLLHUP` after another process such as Bubblewrap has reaped the exited worker; teardown accepts that exact combination as an exit certificate while continuing to reject `POLLERR`, `POLLNVAL`, `POLLHUP` without `POLLIN`, and every other unexpected event combination. Direct-child reaping uses bounded `waitpid(WNOHANG)` retries after pidfd readiness and treats `ECHILD` as already reaped, never as evidence that a process remains alive. It never signals a recycled numeric worker PID or uses a blocking `waitpid`. Standard output and error remain bounded by kernel pipe backpressure; D5 owns the rate-limited trusted drain and log policy.

## Evidence

`plugin-launcher-contract` rejects invalid trusted identities, missing resource enforcement, escaped duplicate JSON authority keys, and an `execve` format failure through the explicit handshake. The fake resource controller asserts the exact B5 descriptor, resource, and timeout contract.

The contract test also forks a real child, opens its pidfd, observes exit before reap, reaps it with `waitpid`, then requires the same production exit-event predicate to accept the kernel's deterministic post-reap `POLLIN|POLLHUP` state and reject error, invalid, and incomplete states. This regression was added after the G4 Release aggregate exposed an intermittent real-Bubblewrap `action channel teardown failed`: the worker was already dead and reaped, but the launcher had required exactly `POLLIN`. After the correction, the full Release aggregate passed 54/54 outside managed confinement, Debug fake and real brokered-action teardown each passed 100 consecutive runs, Release fake and real each passed 50 consecutive runs, and both sanitizer modes passed.

`plugin-launcher-malicious-peer` launches a synthetic unsandboxed worker through the real FD/barrier/pidfd machinery. A forked descendant inherits FD 4 and sends an otherwise well-formed claim for its parent, but C7 rejects it because the kernel sender PID differs from the bound worker. Valid parent traffic on control and render remains accepted, proving the rejection is identity enforcement rather than a broken channel.

`plugin-launcher-bwrap` runs the real B5 Bubblewrap plan against synthetic B6 revision/state resources. It proves inner PID/UID/GID `1/0/0`, exactly FD 0 through 5, `NoNewPrivs=1`, exact rlimits, outer `SCM_CREDENTIALS`/pidfd binding, descriptor-injection quarantine, barrier ordering, and bounded teardown.

`plugin-launcher-systemd-scope` uses the real systemd user manager rather than the fake controller. After the worker reports ready, the test reads its actual unified cgroup and verifies the Omarchy generation scope plus `memory.high=384 MiB`, `memory.max=512 MiB`, `pids.max=16`, `cpu.weight=20`, and a 50% CPU quota. It also verifies `io.weight=10` when the user slice delegates the IO controller. The current development host does not expose `io.weight` in the worker cgroup, so IO controller delegation and enforcement remain an explicit disposable-VM gate even though C7 submits the frozen B5 `IOWeight` property. All tests use finite deadlines and synthetic resources; no active plugin, home, bus payload, display, agent, or device is placed in scope.

Run the focused gate outside a managed outer sandbox that denies `SO_PASSCRED`, user namespaces, or the systemd user bus:

```bash
cmake -S native/plugin-runtime -B build/plugin-runtime-c7 -G Ninja -DBUILD_TESTING=ON
cmake --build build/plugin-runtime-c7 --target omarchy-plugin-launcher-test
ctest --test-dir build/plugin-runtime-c7 --output-on-failure --tests-regex '^plugin-launcher-(contract|malicious-peer|bwrap|systemd-scope)$'
```

## Remaining VM and integration gates

C7 does not claim installed worker startup because C5 still owns the real QML worker and steady-state seccomp transition. D1 must connect activation/discovery, broker framing, readiness, and the daemon event loop. D5 must implement health checks, rate-limited output draining, crash budgets, restart backoff, and session-wide teardown. Disposable-VM tests still own cgroup exhaustion, OOM behavior, hostile descendant trees, service restart limits, installed paths and ownership, supported-kernel variation, session shutdown, and denial of real compositor, D-Bus, agent, GPU, input, audio, camera, and cross-plugin resources.
