# A2 supplement: Bubblewrap namespace identity

## Result

The executable fixture under `experiments/plugin-security/channel/bwrap-identity/` proves the worker identity sequence through a production-shaped Bubblewrap launch with separate user, PID, IPC, UTS, network, and mount namespaces and a separate cgroup namespace when supported. The supervisor does not assume that the PID returned by `fork()` is the worker. It holds the sandbox behind a startup barrier, reads Bubblewrap's `--json-status-fd` record, opens a pidfd for the reported outer `child-pid`, and only then releases the worker. Each launch receives exactly three unnamed `SOCK_SEQPACKET` endpoints at a fixed worker ABI: FD 3 is supervisor control, FD 4 is capability-broker RPC, and FD 5 is render/input transport.

The launch uses `--as-pid-1`, so the outer broker observes Bubblewrap's reported `child-pid` as the sender PID through kernel-supplied `SCM_CREDENTIALS`, while the worker sees itself as PID 1. The explicit one-user mapping makes the worker UID and GID 0 inside the sandbox while the outer broker sees the caller's normal host UID and GID. UID equality is therefore a sanity check, not a plugin identity or cross-plugin discriminator. `--as-pid-1` does not prevent `fork()`: the fixture deliberately forks an unbound descendant, has it send otherwise-valid traffic on all three inherited endpoints, and proves that every packet is rejected because its kernel-supplied outer PID differs from the bound worker PID. The PID-1 worker then reaps that descendant.

An initial run without `--as-pid-1` measured a different topology: Bubblewrap reported the outer PID of its namespace reaper, while `SCM_CREDENTIALS` named the separate PID-2 application process. The two outer PIDs happened to be adjacent in that run, but adjacency is not an identity contract. The first secure worker therefore uses `--as-pid-1` and prohibits unsupervised descendants. If later compatibility requires child processes, the supervisor must either launch them as separate workers with distinct endpoints or introduce a trusted in-sandbox reaper plus a second authenticated readiness barrier that binds a pidfd to the application PID observed through kernel credentials.

Before creating any socket or pipe, the supervisor normalizes a missing FD 0, 1, or 2 to `/dev/null` with the appropriate access direction. Before relocating the three role endpoints plus Bubblewrap's status and barrier descriptors, the launcher duplicates every source into a disjoint high-numbered range, closes each non-destination original, installs all five fixed destinations, and uses `close_range` to close the entire non-allowlisted descriptor space before executing Bubblewrap. This two-phase relocation is collision-safe even when a source descriptor is another entry's destination. A second CTest mode intentionally occupies every descriptor through FD 21 before creating the channels; the resulting source descriptors all sit above the fixed ABI range, yet the sandbox still receives exactly the intended allowlist. Three more modes begin with stdin, stdout, or stderr individually closed and prove that no normalized standard descriptor aliases FD 3, 4, or 5; the closed-output mode remains observable through its checked process exit and CTest result. This is required because a CTest run demonstrated that Bubblewrap can preserve an unrelated harness descriptor even when a direct terminal run happens to have none. The worker enumerates its complete `/proc/self/fd` table and verifies that only standard FDs 0 through 2 and role FDs 3 through 5 survived, excluding the transient descriptor used for enumeration itself. It immediately restores `FD_CLOEXEC` on all three role endpoints before plugin-controlled work.

The launcher executes the pinned `/usr/bin/bwrap` path with `execve`, not a `PATH` lookup, and supplies only `PATH=/usr/bin` and `PWD=/` to the pre-Bubblewrap process. Inside the sandbox, `--clearenv` is followed by explicit `PATH=/usr/bin` and `PWD=/app`, and the UTS namespace receives the fixed `omarchy-plugin` hostname. The startup-barrier write cannot terminate the supervisor because SIGPIPE is ignored and a closed reader becomes an ordinary checked `EPIPE` failure.

Bubblewrap's status interface is JSON Lines, not a fixed pair of lines. The fixture keeps a bounded buffer, permits multiple records in one read, caps each line at 4096 bytes, caps each search at 32 records under one five-second deadline, ignores unknown objects and members as Bubblewrap requires, rejects duplicate top-level authoritative keys, and accepts `child-pid` and `exit-code` only as range-checked JSON integers. A record containing both authoritative fields preserves both rather than discarding the early exit code. The experiment uses the already-installed json-c 0.19 parser to avoid a security-sensitive handwritten JSON parser. That is an explicit spike dependency, not yet a production dependency decision: production should reuse an existing robust parser in the selected native host or introduce a tiny audited status parser rather than add json-c solely for two fields without considering package and attack-surface cost.

Every worker-channel receive polls the retained worker pidfd beside the role socket, rejects a readable pidfd even when a packet is queued, treats `POLLNVAL` or any other unexpected nonzero pidfd event as fatal rather than alive, and checks the pidfd again after `recvmsg` before accepting the packet. A focused injection closes the pidfd after queueing an otherwise correct same-process credential packet and proves that `POLLNVAL` rejects it. The worker stays alive behind an explicit acknowledgement until all intended messages have been validated, avoiding a false race in the positive case. It then forks an inherited-endpoint holder and exits as PID 1; Linux PID-namespace teardown kills that remaining descendant, the worker pidfd becomes readable, and all three sockets expose no queued post-lifetime traffic. The proof therefore binds acceptance to the retained process lifetime rather than only to a matching numeric credential. A direct-child cleanup guard is installed immediately after the monitor fork so failure to acquire the monitor pidfd still kills and reaps it through bounded `waitpid(..., WNOHANG)` polling; a deterministic child fixture proves the guard returns and reaps without a blocking wait, and the pidfd-backed cleanup replaces that guard once acquisition succeeds.

The trusted side stores an expected role beside each endpoint; the role is never selected from a message. The adversarial exchange sends a broker request over control, a render message over broker, and a control message over render. Every packet has the correct kernel PID/UID/GID but is rejected because its declared role and message kind do not match the trusted endpoint binding. A subsequent valid message on each endpoint is accepted, proving the rejection is role enforcement rather than a broken channel. After the exchange the worker exits, and the supervisor requires the already-open pidfd to become readable. Bubblewrap's final JSON status and monitor exit status must also both report success.

## Launch shape

The fixture uses these relevant Bubblewrap controls:

- `--unshare-user`, `--unshare-pid`, `--unshare-ipc`, `--unshare-uts`, `--unshare-net`, and `--unshare-cgroup-try`.
- `--disable-userns` and the supported Bubblewrap 0.11.2 `--assert-userns-disabled` check to prevent the worker from creating nested user namespaces and fail launch if that protection could not be installed.
- `--uid 0 --gid 0` with the caller's single UID/GID mapping.
- An absolute `/usr/bin/bwrap` `execve` with a minimal pre-Bubblewrap environment, followed by `--clearenv`, explicit `PATH` and `PWD`, and a fixed hostname inside the new UTS namespace.
- `--new-session`, `--die-with-parent`, `--as-pid-1`, and `--cap-drop ALL`.
- A new `/proc`, minimal `/dev`, private `/tmp`, read-only `/usr`, and only the probe executable mounted read-only at `/app/worker`.
- Three inherited unnamed `SOCK_SEQPACKET` endpoints at FDs 3 through 5, Bubblewrap's JSON status pipe, and `--block-fd` startup barrier.

This is production-shaped identity and namespace evidence, not the complete sandbox policy. The later sandbox contract still owns the exact runtime library/QML mounts, seccomp policy, cgroup limits, output capture, descriptor allowlist, plugin revision mount, resource accounting, and termination policy. The broad read-only `/usr` mount remains intentionally limited spike scaffolding.

## Observed identities

The successful proof ran with Bubblewrap 0.11.2 on Linux 7.1.8. The managed command sandbox rejected `SO_PASSCRED` with `EPERM` before namespace creation; rerunning the unchanged focused test through the approved out-of-sandbox path succeeded. This confirms that the failure was imposed by the test runner's outer sandbox rather than by the Bubblewrap launch shape.

One successful run prints a record with this shape:

```text
bwrap_pid=<monitor> reported_outer_worker_pid=<worker> scm_pid=<worker> broker_uid=<host-user> scm_uid=<host-user> inner_pid=1 inner_uid=0 unexpected_fds=0 control_fd=3 broker_fd=4 render_fd=5 role_substitution=denied descendant_sender=denied reserved_fd_collision=<denied|not-exercised> pidfd_exit=readable
```

The enforced relationships are:

- `bwrap_pid != reported_outer_worker_pid`.
- `reported_outer_worker_pid == SCM_CREDENTIALS.pid` in the broker's PID namespace.
- `SCM_CREDENTIALS.uid == getuid()` and `SCM_CREDENTIALS.gid == getgid()` in the broker's user namespace.
- The payload reported from inside the sandbox has PID 1, UID 0, and GID 0.
- FDs 3, 4, and 5 are the only nonstandard descriptors in the worker's complete `/proc/self/fd` table, and all three are close-on-exec before plugin-controlled work begins.
- Correctly credentialed broker traffic on control, render traffic on broker, and control traffic on render are all rejected from the trusted endpoint binding; valid traffic on each role is accepted.
- Otherwise-valid traffic from a forked descendant is rejected on control, broker, and render because `SCM_CREDENTIALS.pid` does not match the bound worker PID.
- The occupied-reserved-FD test proves the fixed FD mapping does not depend on lucky source descriptor allocation.
- Closed-stdin, closed-stdout, and closed-stderr modes prove normalization occurs before channel allocation and standard descriptors do not alias a role endpoint.
- The pidfd is not readable while the startup barrier is held and becomes readable after the worker exits.
- Every receive checks that pidfd alongside the socket and again after receipt; invalid or unexpected pidfd poll state is fatal, and a forked inherited-endpoint holder is killed by PID-namespace teardown and leaves no acceptable post-exit packet.

Plugin identity remains the trusted supervisor's immutable endpoint binding containing canonical plugin ID, revision, role, and generation. Neither the translated kernel UID nor either PID is a plugin-selected identity. The outer PID and pidfd constrain which supervised process may speak on that bound endpoint and prevent a passed descriptor or recycled numeric PID from silently becoming the expected worker.

## Running the proof

Run from the repository root:

```bash
bash experiments/plugin-security/channel/bwrap-identity/test.sh
```

The managed command sandbox may reject user-namespace or `SO_PASSCRED` operations with `EPERM`. In that environment the focused test must run through the normal approved out-of-sandbox test path. The fixture itself writes only to its `mktemp` build directory; Bubblewrap constructs an ephemeral mount namespace and mounts the already-built probe read-only.

## Contract consequences

- Use Bubblewrap `--json-status-fd` to obtain the worker PID expressed in the supervisor's PID namespace; do not bind the endpoint to the PID returned when launching Bubblewrap.
- Acquire and retain a pidfd before releasing a supervisor-owned startup barrier. Failure to obtain it aborts launch.
- Relocate the explicit allowlist and close every other descriptor before executing Bubblewrap; do not rely on Bubblewrap to sanitize its caller's descriptor table.
- Stage every descriptor into a disjoint range before assigning any fixed destination; sequential `dup2` relocation is unsafe when sources and destinations overlap.
- Normalize FD 0/1/2 before allocating channels or pipes, close each non-destination original after staging, and test every closed-standard-descriptor case.
- Keep the initial worker as PID 1 and disallow unsupervised descendants. Do not infer the application PID from numeric adjacency when using Bubblewrap's default PID-1 reaper.
- Treat `SCM_CREDENTIALS.pid` as a per-message process check against that outer worker PID and pidfd lifetime, not as the canonical plugin identity.
- Poll the pidfd with each endpoint receive and recheck it after `recvmsg`; only zero events mean alive, `POLLIN` means exited, and every invalid or unexpected nonzero event fails closed. Queued credentials alone are insufficient once the bound worker lifetime has ended or become ambiguous.
- Treat `SCM_CREDENTIALS.uid` and GID as translated namespace sanity checks only. Multiple plugins launched by the same user have identical outer credentials.
- Freeze the initial worker FD ABI as control FD 3, broker FD 4, and render/input FD 5. The trusted endpoint object supplies the role; a role or message kind in plugin payload data may only be checked for consistency and can never redirect dispatch.
- Keep the endpoints separate so broker or render floods cannot consume the supervisor control queue and so each receiver has its own message grammar, size bounds, and descriptor policy.
- Give helper processes distinct endpoints. Set the worker channel close-on-exec immediately after startup so arbitrary plugin-launched children cannot inherit it.
- A new worker generation requires new endpoints, a new reported outer PID, and a new pidfd; reconnects never reuse the old binding.
- Bound launch, status parsing, channel waits, monitor exit, and failure cleanup. On failure, signal the worker and monitor through already-open pidfds and reap the monitor rather than trusting recycled numeric PIDs or an unbounded `waitpid`.
