# `Quickshell.Io` worker compatibility

This worker-owned module preserves the authority-free portion of the familiar `Quickshell.Io` API without loading the host Quickshell plugin.

`FileView` reads only UTF-8 regular files inside the immutable plugin package through `runtime.readPackagedText`. Relative paths and canonical `file:///plugin/` URLs are accepted. Absolute host paths, traversal, symlinks, writes, and watching are unavailable. Private mutable state remains available through `Omarchy.PluginPresentation.PrivateStorage`, whose keys and quotas are broker-enforced.

`StdioCollector` is bounded plugin-local text state. Pure QML has no `QByteArray` value source, so `data` is a string compatibility projection. Adapters should use `setText`, `append`, and `clear`; collected text is capped at one MiB even if a plugin raises `maximumBytes`.

`Process` is intentionally absent. The current manifest sidecar contract describes long-lived helpers launched once before QML and provides no callable, authenticated QML channel. Mapping arbitrary `command` arrays to broker requests would be ambiguous and would conceal authority. A future compatible `Process` requires a manifest-declared command identity, immutable executable identity, bounded argv/stdin/stdout, cancellation and concurrency limits, and a pre-created descriptor protocol that does not add `execve`, `socket`, or `connect` to the steady-state worker.
