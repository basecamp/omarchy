# Plugin sidecars

Schema-v2 plugins may declare bundled sidecars under `runtime.sidecars`:

```json
{
  "runtime": {
    "apiVersion": 1,
    "qml": "ui/Main.qml",
    "sidecars": [
      {
        "name": "indexer",
        "command": ["bin/indexer", "--socket", "/run/plugin/indexer.sock"]
      }
    ]
  }
}
```

The executable is always the first command element and must be an exact normalized relative path inside the plugin revision. Bare executable names, absolute host paths, `..`, symlinks, special files, and non-executable files are rejected. The executable bytes and executable mode are part of the immutable revision identity. Sidecar names are unique canonical identifiers, and the manifest bounds both the sidecar count and argument count and size.

Sidecars are intended to run beside the QML worker in one Bubblewrap sandbox. They may communicate with QML through sandbox-private files, Unix sockets under `/run/plugin`, standard streams arranged by the trusted supervisor, or private loopback. That communication needs no capability because it does not leave the plugin's isolation boundary.

Sharing a sandbox does not confer broker authority. The QML worker retains the authenticated structured broker channel. A sidecar has no broker descriptor by default and cannot turn an internal request into a host effect. Any future direct sidecar broker endpoint must have its own explicit protocol, authenticated process identity, manifest binding, grants, and operation validation.

The QML worker remains the Omarchy-owned sandbox init and PID 1, preserving the broker channel's existing kernel credential binding. Before loading any plugin QML it reparses the read-only manifest, forks only the declared sidecars, closes every descriptor from 3 upward in each child except a close-on-exec startup handshake, and calls `execve` on the exact `/plugin/<declared path>`. There is no shell or executable lookup. After all exec handshakes succeed, the QML worker negotiates its channels, installs the steady-state seccomp filter, and loads plugin QML. It reaps sidecars and treats an unexpected exit as a generation failure. Normal exit terminates and reaps direct sidecars; the host's existing generation-cgroup teardown kills any hostile descendant tree on deadline.

`plugin-sidecar-supervisor` covers exact exec failure, descriptor closure, health, reaping, and teardown. `plugin-sidecar-real-bwrap` repeats the descriptor and teardown assertions with the supervisor as PID 1 inside real user, PID, IPC, UTS, and network namespaces. The real-Bubblewrap test must run outside development wrappers that deny namespace setup.
