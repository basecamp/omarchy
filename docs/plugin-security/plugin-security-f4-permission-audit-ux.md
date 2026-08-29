# F4 permission UX and audit comprehensibility

## Result

The secure schema-v2 reference path now has an explicit whole-policy review implementation rather than requiring users to infer an install or update from one capability's JSON preview. The directly tested `omarchy-plugin-permission-store review` binary displays the canonical plugin ID, complete immutable revision digest, complete policy fingerprint, generation, active/candidate target, and every permission delta. It labels each request as required or optional, uses stable capability wording, renders the bounded scope in plain language, and says whether an earlier grant was inherited. It is deliberately not routed as an end-user `omarchy` command until package ownership and product activation land together.

New, expanded, incomparable, and required/optional-changed requests require typing exactly `grant` or `deny` for each capability. A denial is valid for either an optional or required request; a required denial deliberately leaves the candidate unable to activate. Narrowed, removed, and unchanged authority is shown but does not manufacture a new consent decision. The existing single-capability `grant`, `deny`, and `revoke` commands remain available for inspection and administration, and `diff --format human` renders the same full review without mutation.

The review command checks for a real terminal before its first mutation. `--yes`, `-y`, caller-selected actors, and unattended decision input remain rejected. An unattended install/update may proceed only when the complete delta contains no decision-bearing authority expansion, in which case the output explicitly states that no new or expanded authority requires a decision. JSON remains the default for `list` and `diff`; human formatting is opt-in so existing automation is not silently broken.

## Spoof resistance and surface identity

Permission prompts never use a display name as identity and never abbreviate the revision or policy fingerprint. A plugin-controlled reason string is not presented as trusted explanation because the B2 request contract intentionally carries canonical capability, scope, and required status rather than prose. A future graphical prompt may add manifest prose only if it is visually marked as publisher-supplied and remains subordinate to the trusted canonical fields.

The current permission CLI is a trusted host-side administration tool. It does not accept an actor flag, plugin-selected capability wording, a generic scope, arbitrary provider bytes, or an SDK claim that an operation is safe. Its four current capability labels are a presentation map over the closed B2 registry; an unknown registry entry falls back to its canonical ID instead of receiving invented reassuring prose.

## Audit inspection

The directly tested `omarchy-plugin-audit-store` native inspector spells closed audit enums as outcomes and actions such as `DENIED — plugin operation decided`, `permission revoked`, `stale plugin generation`, and `user gesture already used`. Every record shows the canonical plugin ID, full revision, generation, trusted producer, capability/version, named operation, decision, and correlation when applicable. It contains no plugin message, manifest reason, path, URL, payload, notification text, storage key/value, token, or response body. TSV remains available for exact machine processing with `--format tsv`; no end-user router command advertises the inspector in the dormant reference release.

The human formatter reads only C3-validated records and does not reinterpret worker-controlled logs. Filtering by plugin uses the canonical bounded plugin identifier. Failed or corrupt audit stores remain errors rather than an empty reassuring history.

## Proof

- `plugin-grant-store-cli` freezes existing JSON, verifies the full human identity and required/scope wording, proves noninteractive `grant` and whole-policy `review` leave no store, and uses a pseudoterminal to record an explicit optional denial plus required grant.
- `plugin-audit-store` verifies stable human vocabulary, full revision identity, capability and operation names, grant decision wording, and payload redaction.
- `plugin-audit-store-cli-help` verifies the installed inspector describes itself as trusted and redacted.
- `./test/cli` verifies both user-facing wrappers remain executable, metadata-valid, safely routed commands.

The focused strict build and tests run headlessly. Release and sanitizer configurations cover the permission store/CLI, permission contract, audit store/inspector, and manifest contract. No test reads or modifies the active user's plugin, grant, or audit state.

## Honest boundary

The existing schema-v1 `omarchy plugin add/update/enable` commands remain explicitly unsafe compatibility behavior and do not receive this granular-permission UI or sandbox claims. Wiring schema-v2 discovery and lifecycle staging into those product command names belongs to the later rollout/packaging switch; F4 provides the reviewed reference interaction and inspector without disguising v1 as secured. A graphical surface still needs trusted chrome that cannot be covered by plugin pixels, authenticated invocation of the same grant-store decisions, keyboard/focus hardening, and disposable-VM spoof testing.
