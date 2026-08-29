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

The manifest and immutable-revision validation described above are implemented. Launching sidecars is not yet implemented: the current launcher deliberately runs the QML worker as PID 1, forbids descendants, and binds broker credentials to that one process. The launch implementation must change to a trusted Omarchy init as PID 1 that starts only the fixed QML worker and validated sidecar commands, reaps all children, treats required-process failure as generation failure, and tears down the complete cgroup. Until that supervisor lands, a manifest containing sidecars is validatable but must not be activated as a sidecar-bearing runtime.
