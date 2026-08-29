# C3 durable authoritative audit writer and inspector

## Result

The standalone Qt-free C++20 component under `native/plugin-runtime/audit/` persists only validated B2 `AuditDraft` values. Its API has no free-form message, provider payload, path, URL, token, command, response body, or arbitrary metadata field. The trusted caller selects one of B2's four producer enums and supplies a closed draft; C3 assigns sequence and timestamps itself before publication.

This is the durable evidence store and redacted inspector boundary, not a worker logging service. A worker cannot name the producer, choose the durable sequence, choose timestamps, or append bytes directly. D4 must translate trusted lifecycle, broker, provider, and surface outcomes into B2 drafts rather than forwarding worker text.

## Owner-only store and fixed format

The caller supplies a dedicated directory. C3 creates the final directory with mode `0700`, opens it with `O_DIRECTORY | O_NOFOLLOW`, verifies effective-uid ownership and the absence of group/other permission bits, and holds an exclusive `flock` for every operation. The one published `audit.snapshot` file is created as mode `0600` and reopened with `O_NOFOLLOW`; non-regular files, wrong ownership, broader permissions, and snapshots larger than the hard 4,096-record bound fail closed.

The version-1 binary snapshot has a fixed 32-byte header containing the 16-byte magic, network-order version, last durable sequence, and bounded record count. Each record is a length-prefixed frame of at most 512 bytes. It contains only B2's identities, bounded enums, registered operation/capability values, nonnegative closed metrics, authoritative sequence/times, and the frozen B2 audit-record fingerprint. Decoding bounds the outer file before allocation, record count before reservation, every frame before slicing, every string before construction, and metric count before insertion. It then reruns B2 validation and verifies the fingerprint.

Records must be contiguous and oldest-first, and the header's last sequence must equal the newest record. Truncation—including a zero-length committed file—invalid magic/version/count/length/presence fields, duplicate or unknown metrics, invalid registry values, reordered/gapped sequences, trailing bytes, and fingerprint mismatch are corruption. C3 never repairs corruption by resetting the log or guessing a sequence.

## Authoritative time and durable sequencing

C3 assigns `wall_seconds` from `CLOCK_REALTIME` and a nanosecond timestamp from `CLOCK_BOOTTIME`. Sequence starts at one and advances from the durable header. The persisted monotonic field is made strictly increasing: if the host rebooted or the observed boot clock does not exceed the prior retained value, C3 advances the prior value by one. Sequence or monotonic overflow fails closed. The result is deterministic ordering across restarts without trusting producer timestamps; wall time remains presentation context and may reflect ordinary clock correction.

## Atomic append, recovery, and retention

Append loads and fully validates the current snapshot, validates the new B2 draft, assigns authority fields, encodes and fingerprints it, and drops the oldest record when the configured retention count is exceeded. The complete next snapshot is written to `.audit.tmp`, synced, renamed over `audit.snapshot`, and followed by a directory sync. Retention and append are therefore one transaction; a crash cannot publish a new sequence while retaining an out-of-bound set.

Recovery removes an unpublished temporary and strictly validates the committed snapshot. A configured retention reduction is applied as another atomic snapshot transaction while preserving the durable last sequence. A failure before rename leaves the old snapshot. A failure after rename is an ambiguous commit result and recovery observes the complete new snapshot; after any ambiguous result the caller rereads the inspector instead of retrying under an assumed sequence.

The reference snapshot rewrite is intentionally simple and bounded. It is not an append-only tamper-proof ledger against the trusted Unix uid. Workers cannot access the directory under the sandbox model; a hostile process already running as the supervisor uid is outside this component's integrity boundary. A future journal or database can replace the physical representation only if it preserves the same validation, authority, redaction, crash, and ordering rules.

## Deterministic inspection and export

Queries filter by bounded sequence interval and optional canonical plugin, producer, event, or outcome. Result count is explicitly bounded and records remain oldest-first. TSV export has a fixed column order, numeric enum spelling, canonical ids, numeric metrics, and the B2 fingerprint. It performs no provider lookup and cannot add diagnostic text. Capability ids are from the static B2 registry, while plugin and revision identities are already canonical validated fields.

## Evidence

The focused test covers authoritative producer/time/sequence assignment, B2 draft rejection, strict monotonic ordering, owner-only modes, bounded oldest-first retention, deterministic filtering/export, all three write/sync/rename fault boundaries, ambiguous-commit recovery, orphan temporary cleanup, ordinary and zero-length torn snapshots, symlink denial, and unsafe-root denial. The standalone project also runs B1/B2 contract tests.

Run from the repository root:

```bash
cmake -S native/plugin-runtime/audit -B /tmp/omarchy-plugin-audit -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-audit
ctest --test-dir /tmp/omarchy-plugin-audit --output-on-failure
```

For the sanitizer pass, configure a separate build with `-DPLUGIN_SECURITY_AUDIT_SANITIZERS=ON`. C3 intentionally does not edit the shared native root build while C2, C4, and C7 own adjacent integration work.
