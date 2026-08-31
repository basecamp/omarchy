# Trusted provider host

The provider host is the only product path from an authorized dynamic capability to an external service process. Capability definitions describe semantics; a separate trusted provider profile makes an exact adapter tuple available on one machine. A definition without a matching profile remains unavailable.

Profiles are loaded once when the secure runtime is composed from:

- `/usr/lib/omarchy/plugin-security/<runtime-version>/providers.d` for profiles shipped by packages
- `/etc/omarchy/plugin-providers.d` for profiles installed by a local administrator

Every path component must be owned by the trusted runtime user and must not be group- or world-writable. Profiles and executables are opened descriptor-relative with `O_NOFOLLOW`. A profile must be a bounded regular file with the same ownership and write policy. Its executable must be a bounded, executable regular file with the same ownership and write policy.

The profile format is line-oriented and intentionally small:

```ini
schema=1
adapter-class=example.adapter
contract-digest=<64 lowercase hexadecimal characters>
abi-version=1
group=example.provider
executable=/usr/lib/example/provider
executable-sha256=<64 lowercase hexadecimal characters>
arg=serve
```

`arg` may repeat. No other key may repeat, and unknown keys reject the profile. Profiles in one group must pin the same executable path, executable digest, and argument vector. Duplicate adapter tuples reject the whole catalog rather than depending on load order.

The executable is hashed through its already-open descriptor. The catalog retains that descriptor, and the child is launched from it with `execveat(AT_EMPTY_PATH)`. Replacing the pathname after composition cannot retarget a launch.

Each plugin activation gets a separate `ProviderActivation`. It starts no process during catalog loading, permission review, or route preparation. The first authorized invocation starts one persistent process for the trusted profile group with fixed arguments and a minimal fixed environment. Plugin data cannot select a profile, executable, argument, environment variable, or process group.

The host and provider exchange bounded `SOCK_SEQPACKET` frames on file descriptor 3. Requests carry the protocol version, a monotonic correlation identifier, the exact adapter class, contract digest and ABI, the authorized operation and demand scope, and a bounded payload. Responses must return the exact correlation and a bounded success payload. Timeout, crash, truncation, malformed framing, a late or wrong correlation, or an oversized response permanently fails that process for the activation. Stderr is discarded so provider diagnostics cannot leak into shell logs.

Destroying or cancelling an activation closes its channel, kills and reaps every provider process, and prevents restart. The broker's existing live-generation effect lease remains the authority fence around synchronous dispatch, so activation replacement and revocation drain any bounded in-flight call before the route objects are destroyed.
