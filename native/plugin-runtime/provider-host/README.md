# Trusted provider host

The provider host is the only product path from an authorized dynamic capability to an external service process. Capability definitions describe semantics; a separate trusted provider profile makes an exact adapter tuple available on one machine. A definition without a matching profile remains unavailable.

Profiles are loaded once when the secure runtime is composed from:

- `/usr/lib/omarchy/plugin-security/<runtime-version>/providers.d` for profiles shipped by packages
- `/etc/omarchy/plugin-providers.d` for profiles installed by a local administrator

Every path component must be owned by the trusted runtime user and must not be group- or world-writable. Profiles and executables are opened descriptor-relative with `O_NOFOLLOW`. A profile must be a bounded regular file with the same ownership and write policy. Its executable must be a bounded, executable regular file with the same ownership and write policy and without set-user-ID or set-group-ID bits.

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
inherit-environment=XDG_RUNTIME_DIR
invocation-timeout-ms=30000
```

`arg` and `inherit-environment` may repeat. Inherited environment is restricted to the exact allowlist `HYPRLAND_INSTANCE_SIGNATURE` and `XDG_RUNTIME_DIR`, with at most four unique entries and a 4,096-byte value bound; all other process environment remains absent. No other key may repeat, and unknown keys reject the profile. `invocation-timeout-ms` is optional, defaults to 750 ms, and cannot exceed 30 seconds. It is part of trusted provider policy: plugin data cannot select or extend it. Profiles in one group must pin the same executable path, executable digest, argument vector, and inherited environment. Duplicate adapter tuples reject the whole catalog rather than depending on load order.

The executable is hashed through its already-open descriptor. The catalog retains that descriptor, and the child is launched from it with `execveat(AT_EMPTY_PATH)`. Replacing the pathname after composition cannot retarget a launch. Scripts and shebang wrappers are unsupported and fail closed during launch. The child maps `/dev/null` onto standard input, output, and error; keeps only its provider channel on descriptor 3; sets `PR_SET_NO_NEW_PRIVS`; and marks every descriptor from 4 upward close-on-exec before launch.

Each plugin activation gets a separate `ProviderActivation`. It starts no process during catalog loading, permission review, or route preparation. The first authorized invocation starts one persistent process for the trusted profile group with fixed arguments and a minimal fixed environment. Before releasing that process into the pinned executable, the host places it in one exact activation/group systemd scope and verifies the attachment. The scope has fixed memory, task, CPU, and scheduling ceilings. Plugin data cannot select a profile, executable, argument, environment variable, process group, scope, or resource limit.

The host and provider exchange bounded `SOCK_SEQPACKET` frames on file descriptor 3. Requests carry the protocol version, a monotonic correlation identifier, the exact adapter class, contract digest and ABI, the authorized operation and demand scope, and a bounded payload. Responses must return the exact correlation and a bounded success payload. Timeout, crash, truncation, malformed framing, a late or wrong correlation, or an oversized response permanently fails that process for the activation. Stderr is discarded so provider diagnostics cannot leak into shell logs.

The package's `bash.execute` binding uses the generic [brokered command executor](COMMAND_EXECUTOR.md). Command policies remain a separate root-owned declarative layer; the provider host does not interpret argv and the executor does not grant permissions.

The packaged `external.open-uri.https` provider accepts only `{url, presentation}` after broker authorization and a fresh trusted gesture. It reparses both the requested URL and every authorized manifest origin, requires HTTPS, rejects user information and non-default ports, compares normalized ASCII origins exactly, and bounds the URL to 2,048 UTF-8 bytes. `browser-tab` schedules the fixed system `xdg-open`; `web-app-window` schedules the fixed system Chromium with one `--app=` argument. Scheduling crosses the user systemd manager through a derived same-UID runtime bus and returns no browser data to the plugin. The provider never evaluates a command string or accepts an executable, environment variable, unit name, scheme, host, port, or launch argument from plugin input.

The packaged `system.observe` provider exposes two fixed datasets. `packages.summary` runs only the fixed root-owned `/usr/bin/checkupdates` and `/usr/bin/pacman -Qdtq` probes and returns counts, never package names or command output. `compositor.window-rectangles` runs only fixed root-owned Hyprland JSON queries and returns bounded connector names plus workspace-local clipped rectangles with process-lifetime opaque window identifiers; titles, classes, process identifiers, addresses, and raw compositor objects never cross the provider boundary. Its profile inherits only the two compositor-discovery variables named above. Demand scope must enumerate the requested dataset exactly, and plugin input cannot select an executable, subcommand, environment variable, or unsanitized result field.

Cancelling an activation terminates the complete scope, verifies that its unit, cgroup, and descendants are gone, then signals and boundedly reaps the exact direct child through its pidfd and prevents restart. The same fail-closed teardown runs after attachment ambiguity, transport failure, malformed output, timeout, or crash. A bus failure, deadline, partial cleanup, or reap timeout is never reported clean: `cancel()` returns false, `cleanup_pending()` remains true, authorization stays permanently closed, and the exact scope and process authority are retained for a later retry. No provider authority starts unless the process-lifetime cleanup service is ready; destroying an activation with cleanup still pending transfers its exact retained state to that service for bounded retries. The broker's existing live-generation effect lease remains the authority fence around synchronous dispatch, so activation replacement and revocation drain any bounded in-flight call before the route objects are destroyed.
