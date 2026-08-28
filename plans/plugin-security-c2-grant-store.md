# C2 durable grant store and permission CLI

Status: implemented as a standalone Wave 2 slice; root runtime build/install registration is intentionally deferred to the conflict-free integration pass.

## Contract consumed

C2 consumes the B2 capability contract without adding capability identifiers, scope kinds, generic commands, generic filesystem paths, or generic network access. B2 remains authoritative for request validation, canonical policy fingerprints, scope comparisons, update deltas, grant fingerprints, decision validation, revocation modes, and revocation epoch changes.

Every stored revision is bound to the canonical plugin ID, immutable revision digest, source request fingerprint, B2 policy request fingerprint, and nonzero launch generation. A request whose activation binding aliases a stored revision but supplies a different source request fingerprint is rejected. Schema v1 remains unsandboxed host code and is explicitly ineligible for granular grants.

## Store shape and durability

The first format is a dependency-free, bounded binary schema named `OMGRANT` version 1. It stores a monotonically increasing mutation sequence, the next user-decision sequence, at most 1,024 plugins, at most 4,096 decision records, one active and one candidate revision per plugin, and a monotonic epoch floor per declared capability. The complete file is capped at 4 MiB and all nested attacker-controlled collections retain the B2 limits.

The default location is `$XDG_STATE_HOME/omarchy/plugin-security/grants`, falling back to `$HOME/.local/state/omarchy/plugin-security/grants`. The fixed data and lock names are `grants-v1.bin` and `grants-v1.lock`; plugins cannot choose either path. Reads do not create state.

Directory traversal is component-wise with directory file descriptors and `O_NOFOLLOW`; parent traversal and filesystem-root stores are rejected. The final store directory, data file, temporary file, and advisory lock must be owned by the effective user and permit no group or other access. Mutations take an exclusive lock, reload and validate the current state, verify the preview mutation sequence, write a new `0600` temporary file with `O_EXCL`, sync it, atomically rename it, and sync the containing directory. A crash before rename leaves the old file authoritative; orphaned temporary files are ignored. Failure while syncing the directory after a successful rename is an indeterminate durability result and must be surfaced, not retried as though no mutation happened.

## Active and candidate revisions

A first decision creates a candidate revision. For updates, C2 calls B2 `compute_update_delta` against the active revision and copies only the grants B2 explicitly marks inheritable. Added, expanded, incomparable, or requirement-changed authority never inherits. The read-only `diff`/preview operation exposes the entire delta and expected mutation sequence before any candidate is created.

Decisions for a candidate never replace active grants. Lifecycle code may promote a candidate only when its exact activation binding matches and every required capability is granted. Failed activation and candidate discard leave the active revision unchanged. Candidate discard does not reset capability epoch floors.

## Decisions and revocation

`grant` accepts only B2 `interactive_cli` or `trusted_ui` actors, and the implemented CLI can originate only `interactive_cli`. A `reviewed_policy` actor cannot expand authority. A grant scope must be equal to or narrower than the requested scope. A denial records the exact requested scope. Each user decision advances both the global decision sequence and that plugin capability's epoch; optimistic mutation sequence checks force a second review after concurrent changes.

`revoke` is an authority-reducing operation, requires an exact active or candidate binding, delegates to B2 `PermissionAuthority::revoke`, advances the live epoch, and returns B2's `deny-new`, `cancel-inflight`, or `restart-worker` action for downstream enforcement. Revocation is deliberately not fabricated as a user grant/deny decision.

## CLI

`omarchy-plugin-permission` forwards to the native `omarchy-plugin-permission-store` implementation and declares command metadata for the existing router. It provides deterministic JSON for `list`, `diff`, `grant`, `deny`, and `revoke`.

All operations remain behind `OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1` during rollout. Mutation bindings require `--schema-version 2`, plugin ID, revision digest, source request fingerprint, generation, the complete repeated required/optional request set, and a capability. The CLI parses only the closed B2 quota, token, and resource scope forms used by the current registry; it has no command, path, URL, socket, or arbitrary payload escape hatch.

`grant` and `deny` print the machine-readable preview to the terminal, require both standard input and standard error to be terminals, and require typing the exact action. `--yes`, `-y`, and caller-selected `--actor` are rejected. Thus scripts can inspect or revoke but cannot obtain a grant actor. A future trusted UI must authenticate its caller independently before using the C2 library as `trusted_ui`.

## Verification

The native tests cover absent-store reads, schema-v1 rejection, complete update deltas, lack of side effects during preview, reviewed-policy grant rejection, owner-only modes, optimistic concurrency, scoped grants, denial and redecision, monotonic decision sequences and epochs, activation, live revocation, exact generation and source binding, scope-expansion denial, safe inheritance, failed candidate activation, active preservation, candidate discard, deterministic JSON, symlinked state and lock files, permissive modes, orphaned temporary files, path-component symlinks, and truncated state.

The CLI tests freeze empty JSON output and cover the schema-v2 feature gate, explicit schema-v1 unsafe diagnostic, `--yes` rejection, side-effect-free delta output, and non-interactive grant refusal. The standalone subproject supports strict warnings and optional AddressSanitizer/UndefinedBehaviorSanitizer builds.

## Deferred integration and policy choices

- Root CMake registration and package installation are deferred to the coordinated integration pass; the C2 subtree configures and tests independently now.
- Lifecycle wiring must supply the exact manifest source request fingerprint and call candidate activation or discard at the C1 health-check boundary.
- A trusted graphical prompt needs an authenticated host-to-store call path; no environment variable or CLI flag may assert the `trusted_ui` actor.
- Broker/supervisor consumers must subscribe to mutations and enforce returned revocation actions. This slice persists the authoritative epoch but does not invent cross-process notification semantics owned by later nodes.
- Store recovery, backup policy, migration between store schema versions, publisher identity binding, and integrity protection against an already-compromised user account remain later hardening work. Atomic owner-only storage protects against partial writes and path attacks, not a process with the user's full authority.
- Decision history is intentionally fail-closed at 4,096 entries in this reference slice. Retention/rotation needs a separately versioned audit policy before production rollout.
