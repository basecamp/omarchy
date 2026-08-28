# D6 Inventory and migration report integration

## Result

The reference implementation now produces a deterministic, advisory-only map from an existing schema-v1 plugin to a concrete schema-v2 candidate. It composes the bounded C9 scanner with the strict B1 manifest parser and content identity algorithm without importing or executing legacy QML.

The report makes the compatibility boundary explicit:

- `source` records the scanner's advisory content snapshot and every detected current behavior.
- `mapping` is preserved per finding as proposed guidance requiring an author decision.
- `target` records the exact arbitrary-QML surface declarations and capability requests in the schema-v2 candidate manifest.
- `candidateIdentity` identifies the target bytes but does not grant permissions, activate the revision, or claim runtime safety.

Both JSON and Markdown output retain these distinctions. The Markdown form gives reviewers a direct “today to tomorrow” table and prints the exact target surface and scope declarations.

## Representative corpus

The integration test pairs three small legacy fixtures with the secure C10 product fixtures:

| Fixture | Existing behavior detected | Secure target |
|---|---|---|
| Pomodoro | Direct filesystem view, QML process execution, audio command, notifications | Arbitrary remote QML in a bounded bar surface; private storage, named notification category, and named audio cue requests |
| Desktop pet | Direct Wayland/layer import and trusted shell object access | Arbitrary animated transparent QML in a bounded desktop-overlay surface with dynamic bounded input regions and no capability request |
| Fake status | Process-based service call and computed external URL opening | Arbitrary panel QML using one registered typed fake-service capability with exact resource and operation scope |

The corpus proves that full QML expression is retained inside the worker. What changes is authority: compositor surfaces and system effects become host-owned envelopes or exact broker operations.

## Trust properties

- The CLI invokes only the absolute trusted `$OMARCHY_PATH/bin/omarchy-plugin-security-scan` path with an argument vector; it never invokes a shell.
- The scanner process has bounded stdout, stderr, and wall time.
- Scanner output is schema-checked and remains explicitly advisory and schema-v1-unsafe.
- The secure target manifest must be a regular non-symlink file and passes the strict schema-v2 parser and bounded tree identity walk.
- Output is deterministic, and Markdown cells escape plugin-controlled markup.

## Evidence

The focused suite exercises JSON and Markdown generation for all three pairs, repeats each run to prove deterministic identities and output, checks every expected legacy finding and exact target capability/surface declaration, rejects a non-executable scanner, and runs the B1 manifest contract tests transitively.
