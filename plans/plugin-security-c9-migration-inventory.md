# C9 installed-plugin migration inventory

Status: implemented as a report-only extension of the B7 static scanner.

## Outcome

`omarchy plugin security scan --all [--format markdown|json]` inventories the plugin trees Omarchy currently discovers: user-installed plugins under `$HOME/.config/omarchy/plugins` and built-in plugins under `$OMARCHY_PATH/shell/plugins`. It aggregates the B7 finding taxonomy into one deterministic machine report or one author worksheet without executing QML, JavaScript, installers, binaries, Git hooks, or any other plugin content.

The command has no install, update, fix, enable, disable, approve, request, grant, or deny operation. It does not invoke the shell, lifecycle, grant store, broker, package manager, network, or Git. Root override options exist only to make the same read boundary testable against synthetic/pinned trees; they do not select output or mutation paths.

## Discovery boundary

The installed root is flat by the current plugin model. C9 considers every non-hidden immediate entry, reports directory plugins, and explicitly blocks symlink and non-directory entries. Hidden staging entries are counted and ignored because they are not current plugins; their contents are never traversed or executed.

Built-in discovery follows the existing catalog shape: `manifest.json` and `*.manifest.json` files may appear below nested feature directories. Each manifest is a plugin inventory candidate, including multiple widget manifests that share a source directory. A shared directory can therefore have the same static behavior findings in more than one plugin worksheet; this is conservative and visible through distinct manifest source paths rather than silently attributing shared code to only one plugin.

Missing installed or built-in roots are reported as `absent` and produce an explicit empty inventory. A symlinked, unreadable, or non-directory root is `blocked`. A malformed manifest remains a scanned plugin with a high-severity `manifest.invalid` finding. A plugin directory without its expected identity manifest receives `manifest.missing`. A per-plugin bound, race, or read failure produces `status: blocked`, `reason: scan-incomplete`; it never becomes a clean report.

Discovery and scan ordering is lexical and output contains root kinds plus root-relative source paths, not machine-specific absolute paths. Error details replace the selected root path and are truncated. Filesystem names remain untrusted JSON strings and are escaped in Markdown.

## Source and revision identity

Every aggregate record has a `sourceIdentity` composed from the closed source kind (`installed` or `builtin`) and the root-relative directory or manifest path. Where the selected identity manifest parses strictly, the nested identity also records its schema version and author version.

Every completed B7 scan computes an `advisory-content-snapshot-v1` SHA-256 over the sorted root-relative file paths, modes, regular-file bytes, and hashed-in symlink targets observed by that same bounded scan. C9 publishes that value as `revisionIdentity` so repeated worksheets can identify the exact bytes they assessed.

This snapshot is explicitly not B1's canonical immutable tree digest, does not prove the source stayed unchanged after the scan, and is not accepted by activation or grants. Later D6 integration must replace or accompany it with the B1 revision identity when scanning an immutable staged revision. C9 neither parses nor exposes Git origin URLs, which avoids leaking credentials embedded in repository configuration.

## Aggregate report contract

The JSON report has `schemaVersion: 1`, `reportType: installed-plugin-migration-inventory`, `advisoryOnly: true`, and `legacySchemaV1Safe: false`. The first number is the report schema, not a claim that plugin schema v1 is safe. It contains:

- root availability, bounded discovery counts, and hidden installed-entry counts;
- deterministic plugin records with source identity, scan status, explicit incomplete reason, plugin ID when available, advisory revision snapshot, and the unmodified nested B7 report;
- totals for discovered, scanned, blocked, findings, and each closed B7 severity.

The Markdown worksheet repeats that schema v1 remains unsafe host code, gives every scanned plugin its source and advisory snapshot, retains B7's three author-review columns, and calls blocked plugins unreviewed and unsafe. No finding is translated into a capability request, permission suggestion, grant, or claim of safety. The B7 mapping text remains a migration prompt into already reviewed typed operations; exact capability/version/scope selection remains a separate author and security review.

## Bounds and fail-closed behavior

The B7 limits still apply independently to every candidate: 4,096 filesystem entries including directories, 1 MiB per file, 16 MiB of bytes actually read, and 4,096 findings. C9 additionally limits aggregate discovery to 512 plugins and aggregate successful findings to 16,384. Built-in manifest discovery stops after 4,096 filesystem entries. An aggregate limit prevents further reports from being presented as successfully scanned; the affected entry is explicitly blocked.

Traversal retains B7's directory-descriptor, no-follow, post-open type/identity, nonblocking read, and strict duplicate-key JSON checks. Aggregate root and candidate checks are repeated by the B7 no-follow open, so a path swapped after discovery fails rather than being followed. Symlink targets contribute only to the advisory snapshot and are never opened.

## Verification

The end-to-end fixture contains current schema-v1 installed and built-in layouts, nested built-in and shared-directory manifests, process/shell authority, notification and environment behavior, malformed and missing manifests, a symlinked plugin root, and executable hidden staging content.

The frozen aggregate projection covers root status/counts, source paths, plugin IDs, exact content snapshot goldens, finding order, severity totals, scanned/blocked totals, and the symlink reason. Tests fingerprint both roots before and after, set an execution marker that must remain absent, verify hidden staging is ignored, verify every nested report remains advisory and explicitly v1-unsafe, exercise Markdown warnings, exercise absent and symlinked roots, and prove that enable/grant-looking options are rejected. The original B7 fixture and hostile scanner tests remain green unchanged.

## Deferred work

- D6 should run this scanner against B1 immutable revision paths and bind stored author worksheets to B1 tree, manifest, and source-request digests.
- Inventory persistence and author annotations need their own owner-only schema; annotations must never suppress broker enforcement or create grants.
- Shared built-in source directories can be scanned once and referenced by multiple manifest records as a later performance optimization, provided per-manifest identity and deterministic findings remain unchanged.
- Language-aware parsing, native dependency provenance, archive inspection, composed-risk analysis, and detector version migrations remain the B7 deferred work. A clean static report continues to mean only that no current rule matched.
