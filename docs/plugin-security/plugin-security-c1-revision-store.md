# C1 immutable revision store and activation transaction

## Result

The C1 component under `native/plugin-runtime/revision-store/` turns a C0 `VerifiedPlugin` into a supervisor-owned, content-addressed revision and publishes activation state as one durable record. Staging never loads QML, starts the worker, evaluates plugin metadata, or grants authority. Schema v2 must be explicitly enabled in both C0 and C1; schema-v1 plugins never become a `VerifiedPlugin` and remain on the explicitly unsafe legacy path.

The implementation is Linux-specific and Qt-free C++20. It is deliberately below C2 activation orchestration: C2 decides whether required grants are present and supplies the authoritative policy and grant fingerprints. C1 records those fingerprints exactly and never derives, widens, merges, or inherits a new revision's permissions.

## Store layout and ownership

The caller supplies a dedicated store root. C1 creates the final root with mode `0700`, opens it with `O_DIRECTORY | O_NOFOLLOW`, verifies that it is owned by the effective uid with no group or other permission bits, and holds an exclusive `flock` for each operation. The `revisions`, `metadata`, and `state` children receive the same owner and mode checks.

```text
store/
  revisions/<tree-sha256>/  copied plugin tree, directories 0500, files 0400 or 0500
  metadata/<tree-sha256>    exact plugin/tree/manifest/request identity, mode 0600
  state/activation          active and rollback policy bindings, mode 0600
```

The no-write mode is an immutable-store invariant for the trusted runtime, not protection from a hostile process already running as the same Unix uid, which can restore owner write permission. Deployment must keep the store outside publisher-controlled paths and confine plugin workers so they cannot address it. Filesystem-backed immutability such as fs-verity may strengthen this later without changing the content identity.

## Symlink-safe staging transaction

Staging consumes the manifest model and three hashes from a C0 `VerifiedPlugin`. It opens the source root and every source directory/file with `O_NOFOLLOW`, enumerates directory descriptors, inspects names with `fstatat(..., AT_SYMLINK_NOFOLLOW)`, rejects symlinks and non-regular objects, and copies into a private `.stage-*` directory using `openat` and `O_EXCL`. `.git` is excluded exactly as it is in B1. File, directory, per-directory entry, recursion-depth, and byte limits are enforced, and source inode, mode, size, modification time, and change time are compared across each copy.

Files are synced before their directories. Executable provenance is reduced to owner-executable versus non-executable while preserving the executable bit used by the B1 tree identity; all group/other and owner-write bits are removed. The staged manifest is strictly parsed again and B1 recomputes the complete tree identity through the already-open directory descriptor exposed at `/proc/self/fd`, not by resolving the caller's path again. Publication occurs only when the manifest model and all three hashes exactly match the C0 identity. `renameat` publishes the tree at its SHA-256 name and `fsync` makes the revisions-directory update durable.

An existing content-addressed revision is reverified, not trusted by name. Missing metadata after a crash between revision and metadata publication is repaired only after this reverification. Conflicting metadata or stored content fails closed.

## Exact activation and rollback binding

One activation record contains each of these fields for the active target and, when present, the rollback target:

- canonical plugin id;
- tree revision SHA-256;
- exact manifest SHA-256;
- exact source-request SHA-256 from B1;
- authoritative policy SHA-256 supplied by C2;
- authoritative selected-grant SHA-256 supplied by C2;
- nonzero runtime generation.

Before activation, the first four fields must exactly match immutable revision metadata. Policy and grant fingerprints are opaque C2-owned identities. A normal activation must advance the current generation and never copies permissions from the old activation. Rollback restores the exact retained revision, request, policy, and grant identities while assigning a fresh monotonic generation, preventing stale messages from a former instance from becoming current again.

The complete new record is written to an owner-only temporary file, synced, renamed over `state/activation`, and followed by a state-directory sync. There is no intermediate state in which a new revision is paired with old permissions. The old active binding becomes the single rollback target in the same atomic record.

## Recovery and fault semantics

`recover()` removes unpublished staging and record temporaries using descriptor-relative, no-follow traversal. It then strictly parses the activation record and verifies that active and rollback metadata and revision directories still exist. Missing, malformed, substituted, or oversized state fails closed; recovery never guesses a target and never promotes a staged revision.

Injected failures cover staging after copy and after verification, and activation after write, after file sync, and after rename. A failure before rename preserves the old activation. A failure after rename is explicitly an ambiguous commit result: recovery observes the complete new record, matching the standard atomic-rename transaction rule. A real power loss in that last interval may recover either the old or new complete directory entry depending on filesystem guarantees, but never a partially parsed binding; callers must reread state after any ambiguous result.

## Retention

`prune(maximum_revisions)` deterministically removes lexicographically ordered unprotected content-addressed revisions until the bound is met. It never removes the active or rollback tree. If those protected targets alone exceed the requested bound, the operation returns `retention_blocked` without deleting either target. Revision metadata is removed with the tree and both containing directories are synced. Orphan metadata is non-authoritative and cannot activate without its matching revision directory.

## Evidence

The focused test covers the schema-v2 gate, frozen B1 fixture identity, owner-only and non-writable stored modes, idempotent staging, source symlink denial, both staging fault boundaries and clean retry, exact request binding denial, monotonic activation, all three activation fault boundaries, atomic old/new recovery, fresh-generation rollback with exact prior policy/grant identity, and retention protection for active and rollback targets.

Run from the repository root:

```bash
cmake -S native/plugin-runtime/revision-store -B /tmp/omarchy-plugin-revision-store -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-plugin-revision-store
ctest --test-dir /tmp/omarchy-plugin-revision-store --output-on-failure
```

For the sanitizer pass, configure a separate build with `-DPLUGIN_SECURITY_ENABLE_SANITIZERS=ON`. The aggregate native runtime registers C1 immediately after C0 discovery so the same contract is exercised when Qt dependencies are available.
