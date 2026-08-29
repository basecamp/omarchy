# Trusted capability definitions

This contract makes the permission vocabulary extensible without letting plugins define their own authority. Omarchy packages and local administrators install definitions; a plugin manifest can only reference an exact canonical name, definition generation, and definition digest. Unknown, stale, or replaced definitions fail closed.

A definition binds one canonical authority identity to its scope schema, operations, trusted UI title and risk text, gesture requirements, revocation behavior, audit redaction policy, adapter class, adapter ABI, and implementation digest. Publisher rationale remains untrusted manifest prose and is not part of this trusted definition. Two names cannot point at the same authority identity or identical adapter/operation binding, preventing a dangerous adapter from being relabeled as a harmless permission.

The category vocabulary describes durable authority rather than products: bounded network fetch, gesture-bound HTTPS opening, sanitized system observation, opaque device observation/control, constrained media streaming, and exact CLI harness profiles. GitHub, AirPods, Radio Browser, and compositor implementations are trusted adapters registered under those categories, not permission names.

CLI profiles identify one absolute non-shell executable by digest, exact working directory, fixed environment entries, closed subcommands, positional argument grammar, byte limits, and timeout. Authorization returns an argv vector for direct execution; it never produces a command string and rejects `bash`, `sh`, `env`, unknown subcommands, extra arguments, malformed bounded values, and executable replacement. Actual process launch remains an injected trusted callback downstream.
