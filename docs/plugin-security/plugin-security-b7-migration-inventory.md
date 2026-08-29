# B7 report-only migration inventory contract

## Outcome

B7 adds `omarchy plugin security scan <plugin-directory> [--format markdown|json]`, a static migration inventory command. It reads a plugin tree, identifies current behaviors that cross the proposed security boundary, and writes either a deterministic JSON report or a three-column migration worksheet to standard output. It never imports QML or JavaScript, launches plugin executables, evaluates manifests, runs installers, contacts a service, changes a grant, approves a plugin, or writes plugin/system state.

The scanner is migration assistance, not an enforcement control. Every report carries `schemaVersion: 1` and `advisoryOnly: true`; every finding leaves `authorDecision` as `review required`. A clean report does not mean a plugin is safe. B1 manifest validation, immutable staging, B5 sandboxing, B2 grants, and B3/C4 broker enforcement remain authoritative.

## CLI and output contract

The only positional input is a real plugin directory. A symlink root is rejected. The command has no output-file, install, fix, grant, enable, or mutation option. Markdown is the default for an author-facing worksheet; `--format json` provides a stable machine-readable report for C9 and later review tooling.

Successful inventory exits zero even when critical findings exist because severity is not an automated approval or activation decision. Invalid arguments, unreadable/racing input, special bound exhaustion, and incomplete scans exit two without emitting a partial report as if it were complete.

JSON findings have these closed fields:

- `id`: stable detector identifier;
- `severity`: one value from the taxonomy below;
- `path` and `line`: location only, with no source excerpt that could leak credentials;
- `behavior`: bounded detector-owned explanation;
- `mapping`: detector-owned proposed secure API or trusted portal direction;
- `confidence`: `exact` for direct syntax/file evidence or `heuristic` for computed-value inference;
- `authorDecision`: always `review required` in B7.

The Markdown worksheet has exactly the requested conceptual columns: detected behavior, proposed broker/UI mapping, and author decision. It keeps arbitrary visual QML out of the inventory penalty: manifest surfaces map to host-owned remote surface roles, not a declarative component library.

## Severity taxonomy

Severity describes likely migration/security impact, not exploitability and not permission approval.

| Severity | Meaning | Representative findings |
|----------|---------|-------------------------|
| `critical` | Current behavior would pierce the secure process, compositor, bus, command, capture, installer, or privilege boundary and requires redesign or a separately trusted portal | shell evaluation, detached execution, direct sockets/D-Bus/Wayland/screencopy/Hyprland, shell object graph, executable/install content, privileged system mutation, native binaries |
| `high` | Direct access must move behind a narrow scoped broker operation and may expose user or network data | `Process`, `FileView`, network CLI, clipboard, networking/device imports, malformed manifest identity |
| `medium` | A purpose-built broker API is expected and can often preserve product behavior mechanically | notification delivery, named IPC commands, external URL opening, media/audio integration |
| `review` | Static syntax cannot safely enumerate the requested authority or resource scope | computed commands/arguments/paths/URLs, environment reads, symlinks |
| `info` | Inventory context that needs a migration choice but is not itself authority | declared plugin kinds, surfaces, and entry points |

Multiple findings at one location are intentional. `Process` plus `bash -lc`, for example, records both the direct process dependency and the fact that its authority cannot be converted by copying a literal executable name.

## Detector and secure-mapping contract

The first detector set covers the representative corpus requirements:

- plugin kinds and entry points map to host-owned surface envelopes while retaining arbitrary remote QML;
- `Process`, `execDetached`, shell evaluation, `curl`/`wget`, executable files, native binaries, and installers map to registered bounded workers/adapters or manual redesign, never a generic command grant;
- `FileView`, computed paths, environment reads, symlinks, and special files map to private storage, opaque user-selected handles, or immutable-tree repair;
- socket, networking, Bluetooth, and D-Bus access map to reviewed provider-specific adapters, never ambient sockets or buses;
- Wayland, layer-shell, screencopy, Hyprland, clipboard, and capture access map to host-owned surfaces, named compositor actions, or trusted gesture-bound portals;
- URL opening maps to a gesture-bound host/scheme-scoped operation, with computed URLs separately requiring manual host inventory;
- notification, named IPC, and audio/media behavior map to the bounded reference capabilities or future reviewed adapters;
- trusted `shell`, `bar.shell`, registry, and cross-plugin object access maps to versioned settings, state, events, dependencies, and named actions;
- package management, service control, privileged paths, `sudo`, and `pkexec` map only to separately confirmed trusted workflows or removal.

No detector creates a B2 request or grant. The proposed mapping is a worksheet prompt. Capability versions and exact scopes must come from the closed registry after author and security review.

## Read boundary and bounds

Traversal does not follow symlinks and ignores only `.git` metadata. The root and each opened file use directory descriptors, `O_NOFOLLOW` where available, post-open regular-file/type/identity checks, and nonblocking reads so a replaced FIFO/device cannot become an accidental read target. Symlinks and special files are reported without opening them.

Attacker-facing work is bounded to 4,096 filesystem entries, 1 MiB per file, 16 MiB total content, and 4,096 findings. Every bounded regular file is read within those limits to identify ELF/PE magic, but only known source/manifest suffixes, `PKGBUILD`, and executable candidates are decoded and pattern-scanned. Arbitrary binary content is not decoded. JSON manifests reject duplicate keys. Findings are deduplicated and sorted by severity, path, line, and identifier for deterministic fixtures.

The scanner returns a failure instead of a partial worksheet when any bound is exceeded or file identity changes during the scan. C9 must preserve that distinction and must not cache a failed scan as a clean result.

## Known false positives and blind spots

Static inventory is necessarily incomplete. These limitations are part of the contract rather than hidden implementation details.

- Regex detectors recognize syntax, not QML/JavaScript semantics. A locally defined type named `Process`, `Socket`, or `Notification` can be a false positive.
- Comment masking understands JavaScript/QML/C line and block comments and preserves quoted strings. It intentionally does not implement every template-literal interpolation edge case or language-specific parser extension.
- String mentions of URLs or command names alone are not findings, which reduces documentation noise but can miss code that later evaluates stored strings indirectly.
- Computed command, path, and URL detection is heuristic. Aliases, helper wrappers, property indirection, concatenation across lines, generated QML, minified bundles, reflection, and runtime imports can evade it.
- The first slice does not parse every plugin language, native object format, QML module registry, `.desktop` quoting rule, systemd directive, installer framework, or bundled dependency manifest.
- A literal host, executable, path, or operation is evidence of a dependency, not evidence that its proposed scope is complete or safe.
- No data-flow or permission-composition analysis exists yet. Clipboard/capture/credentials plus an output channel still require human composed-risk review even when each individual detector is present.
- `.git` is excluded as repository metadata. Files obtained from submodules, generated during an old install, downloaded at runtime, or stored outside the scanned tree are not inventoried.
- The scanner reads current filesystem bytes, not B1's immutable staged revision identity. C9 must bind reports to the B1 tree/content digest before presenting them as revision-specific evidence.

False-positive handling must narrow detector rules or let the worksheet record an author explanation. It must never add a suppressing manifest directive that converts static scanner silence into runtime authority.

## Fixture and exit evidence

`test/shell.d/plugin-security-inventory-test.sh` is automatically registered by the shell test runner. Its representative fixture includes custom QML surfaces, direct process/shell invocation, private-file-shaped access, an environment-derived computed path, notifications, named IPC, a computed URL, trusted registry access, detached `curl` and Hyprland use, an executable installer, and comment-only examples.

The frozen projection checks detector identifiers, severity, path, line, confidence, counts, deterministic ordering, advisory identity, and unchanged author decisions. Additional hostile cases prove that:

- fixture contents and modes are unchanged and an executable installer is never launched;
- comments do not create findings;
- Markdown retains the three-column worksheet and advisory warning;
- symlinks and FIFOs are reported without following/opening them, and non-executable native binary magic is still inventoried;
- oversized files and symlink roots fail closed;
- duplicate manifest keys are reported by strict parsing.

The normal CLI metadata suite also verifies that the new user-facing command is discoverable and that `--help` is handled by the router without executing the scanner.

## Downstream handoff and deferred work

C9 can consume schema v1 to scan pinned representative revisions and generate the larger ecosystem migration report. D6 can add reviewed author-decision persistence and cross-revision worksheets, but those records remain advisory and separate from B2 grants.

Deferred work includes language-aware parsers, exact QML import resolution, native dependency/provenance inspection, archive and submodule inventory, data-flow and composed-risk analysis, B1 digest binding, SARIF or other interchange formats, detector-version migration, and a reviewed false-positive annotation format. None is required to preserve the fail-closed rule that unimplemented runtime authority remains denied.
