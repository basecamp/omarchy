# A2: Private plugin channel and identity spike

## Result

This historical prototype demonstrates a private, inherited Unix-domain channel whose authoritative plugin identity is assigned by the broker when it launches the worker. The worker may place any `plugin_id` value in a request payload, but that value cannot affect authorization.

The fixture lives in `experiments/plugin-security/channel/` and uses only Linux/POSIX APIs plus the C++ standard library. It intentionally has no Qt dependency. Its forged-identity, packet-boundary, truncation, and descriptor-cleanup cases remain reusable evidence, but its single FD 3 topology and 16-byte experimental header are superseded by [`plugin-security-a2-bwrap-identity.md`](plugin-security-a2-bwrap-identity.md) and [`plugin-security-a2-envelope.md`](plugin-security-a2-envelope.md). They are not production wire fixtures.

## Channel construction and identity binding

The broker creates an `AF_UNIX`, `SOCK_SEQPACKET`, close-on-exec socket pair and launches exactly one worker with one endpoint mapped to file descriptor 3. The endpoint is not named in the filesystem and is not discoverable or reconnectable by another process.

Before launch, the broker records an immutable channel binding containing:

- The plugin ID selected from the broker's verified install record.
- The expected worker PID returned by `fork`.
- The broker-owned socket endpoint.

Both endpoints enable `SO_PASSCRED`. Every received packet must contain Linux `SCM_CREDENTIALS`, and the broker rejects packets whose kernel-supplied PID or UID differs from the launch binding. A payload field never participates in identity selection.

This closes two different substitution paths: knowing a plugin ID is insufficient to claim it, and receiving or guessing payload bytes is insufficient to send on the private channel. Passing the file descriptor to another process also changes the kernel-supplied sender PID and is rejected.

For production, the launch record should retain a pidfd in addition to the numeric PID. That removes ambiguity from PID reuse and gives lifecycle code a race-free handle for termination and exit observation. The prototype's child relationship and short-lived exchange make numeric PID comparison sufficient for this experiment, but not the final broker.

## Versioned framing

Each `SOCK_SEQPACKET` packet is exactly one protocol frame. Multi-byte integers are in network byte order.

| Offset | Size | Meaning |
| --- | ---: | --- |
| 0 | 4 | Magic, ASCII `OMPL` (`0x4f4d504c`) |
| 4 | 2 | Protocol version |
| 6 | 2 | Message type |
| 8 | 4 | Payload length |
| 12 | 4 | Flags, required to be zero in version 1 |
| 16 | N | Payload bytes |

Version 1 permits payloads up to 4,096 bytes. The receiver supplies a fixed 4,112-byte buffer to `recvmsg`, requests `MSG_TRUNC`, and rejects truncated packets, oversized declared payloads, mismatched packet lengths, nonzero flags, invalid magic, and unknown message types before interpreting the payload.

The receiver also rejects `MSG_CTRUNC`, duplicate credential records, and every ancillary record other than the one exact `SCM_CREDENTIALS` structure. Its fixed ancillary buffer can hold the credentials plus Linux's maximum 253 descriptors. After every successful `recvmsg`, it walks the delivered control prefix and closes all `SCM_RIGHTS` descriptors before checking payload truncation, ancillary truncation, or any other error. This ordering matters: `MSG_CTRUNC` means some ancillary data was discarded, but descriptors that fit in the returned prefix may already have been installed in the broker process. Rejecting without closing those delivered descriptors would permit resource exhaustion.

The focused test sends 128 descriptor-bearing messages twice. The first campaign supplies an unexpected descriptor with an otherwise valid frame. The second supplies eight descriptors while deliberately constraining the receiver's control length to force `MSG_CTRUNC`. Both campaigns require rejection and compare `/proc/self/fd` counts before and after the complete receive loop to prove that the broker retains no injected descriptor.

The demonstration uses these message types:

| Value | Name | Direction | Purpose |
| ---: | --- | --- | --- |
| 1 | `HELLO` | Worker to broker | Offer the worker's supported version range |
| 2 | `WELCOME` | Broker to worker | Select the channel version |
| 3 | `REQUEST` | Worker to broker | Request an operation |
| 4 | `RESULT` | Broker to worker | Return a result |

The worker sends `HELLO` with `min=1;max=1`; the broker selects version 1 with `WELCOME`. All subsequent prototype frames use that selected version. Production preserves the authenticated inherited-channel property but replaces this framing with a 40-byte envelope: envelope version 1 carries a role protocol version of zero during `HELLO`, and `WELCOME` selects the role protocol independently on FD 3, FD 4, and FD 5.

## Forged-identity proof

Running the fixture as follows binds the endpoint to `trusted.clock` while instructing the worker to claim `forged.admin` in its request:

```bash
./plugin-channel-spike trusted.clock forged.admin
```

The result contains both facts without confusing them:

```text
authorized_as=trusted.clock;untrusted_payload=plugin_id=forged.admin;operation=storage.read
```

The test asserts that `authorized_as=forged.admin` never appears. Authorization is derived from the broker's endpoint binding after validating `SCM_CREDENTIALS`; `plugin_id=forged.admin` remains inert request data.

## Building and testing

Run the focused test from the repository root:

```bash
experiments/plugin-security/channel/test.sh
```

It configures an out-of-tree temporary CMake build, compiles with warnings as errors, exercises the forged-identity proof, tests frame round-tripping and local oversize rejection, runs repeated normal and truncated ancillary descriptor-injection campaigns, proves that the broker's descriptor count does not grow, and runs the CTest contract.

## Production resolution

- [`plugin-security-a2-bwrap-identity.md`](plugin-security-a2-bwrap-identity.md) proves the Bubblewrap-reported outer PID plus pidfd binding, fixed FD 3/4/5 ABI, endpoint-role substitution denial, close-range allowlist, and pidfd teardown.
- [`plugin-security-a2-envelope.md`](plugin-security-a2-envelope.md) freezes the 40-byte outer header, per-role negotiation, launch generation, common correlation id and cancellation, typed errors, and 4 KiB, 64 KiB, and 16 KiB endpoint payload caps.
- Every endpoint reserves fixed ancillary quarantine for credentials plus up to four delivered descriptors. Control and broker permit zero descriptors; render permits at most one typed host-created descriptor. Every delivered descriptor is closed before an error response or endpoint teardown unless full validation explicitly transfers ownership.
- The trusted daemon strictly matches worker packets to the launch-bound outer PID/UID/GID and retained pidfd. The sandbox worker cannot generally identify the outside daemon PID; it compares namespace-translated per-packet credentials with its inherited endpoint's `SO_PEERCRED` baseline, permits legitimate PID-zero translation, and treats that check as defense in depth rather than authority.
