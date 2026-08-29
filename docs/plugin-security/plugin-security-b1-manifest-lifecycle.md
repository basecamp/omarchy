# B1 manifest v2 and lifecycle contract

## Result

The independent C++20 contract under `native/plugin-runtime/contracts/manifest/` defines the schema-v2 manifest model, canonical content identities, requested-capability fingerprint, and revision activation state machine without depending on Qt, json-c, OpenSSL, the future B0 build, or the schema-v1 QML and shell implementation. It configures and tests as its own CMake project so Wave 1 lanes can consume the contract before the native host exists.

B1 does not assign meaning to a capability or its scope. It gives B2 the capability id, required-versus-optional class, human reason, and canonical bytes for the remaining request members. B2 owns registry lookup, scope validation, subset comparison, grants, and authorization. B3 owns the broker encoding and must not use a manifest field as channel identity.

## Strict manifest-v2 model

The root object requires exactly `schemaVersion`, `id`, `name`, `version`, `runtime`, `surfaces`, and `permissions`; `description` is optional. Unknown root and runtime fields are rejected so misspelled security-relevant fields cannot be silently ignored. `schemaVersion` must be the integer 2 and `runtime.apiVersion` must be the integer 1.

Plugin and capability ids are canonical lowercase ASCII identifiers of at most 128 bytes. Separators `.`, `-`, and `_` cannot lead, trail, or repeat. Names, versions, reasons, arguments, strings, container counts, nesting, and total manifest bytes are bounded. The parser rejects duplicate decoded object keys, trailing input, malformed or non-shortest UTF-8, invalid surrogate pairs, control characters, integer overflow, leading-zero numbers, and non-integer JSON numbers. Canonical JSON sorts decoded object keys, emits integers in shortest decimal form, and emits strings with one deterministic escaping rule.

`runtime.qml` is a normalized relative path. An optional nonempty `runtime.worker` array contains a normalized relative executable path followed by bounded arguments. Absolute paths, empty components, `.`, `..`, backslashes, NUL, and non-normal spelling are rejected. Content identification verifies that the QML and worker entry points are regular files in the tree.

When a worker entry point is declared, at least one executable permission bit must be present and that bit participates in the tree identity. This is provenance of the packaged executable bit, not authority to execute outside the B5 sandbox.

`surfaces` must be an object and is retained as canonical opaque JSON for B4. `permissions.required` and `permissions.optional` must both be arrays. Each request requires one unique canonical capability id and a nonempty bounded reason. Every other request member is retained as one canonical scope object. A capability cannot appear in both classes or more than once in either class.

The initial numeric profile is deliberately integer-only. A later B2 or B4 contract that needs a fractional manifest value must freeze an unambiguous canonical numeric representation and update the schema version or compatibility rule before B1 accepts it.

## Frozen SHA-256 identities

B1 uses SHA-256 implemented inside the dependency-free contract. Tests include the standard empty-input and `abc` vectors. The implementation choice avoids making the spike-only json-c dependency or a new crypto package part of the production contract; a future host may replace the implementation with a packaged cryptographic library only if it reproduces the same bytes and goldens.

The manifest digest is SHA-256 over the exact `manifest.json` bytes. It identifies presentation text and formatting changes as code-revision changes.

The tree digest hashes this unambiguous stream:

1. Domain separator `OMARCHY-PLUGIN-TREE-V1` followed by NUL.
2. Big-endian 64-bit file count.
3. For every regular file in ascending normalized relative-path byte order: big-endian 64-bit path length, path bytes, one byte whose value is 1 when any executable bit is set and 0 otherwise, big-endian 64-bit content length, and exact content bytes.

`.git` and its descendants are excluded. Symlinks and all non-regular, non-directory filesystem objects are rejected. A tree is limited to 4,096 files and 64 MiB. The frozen minimal-fixture tree digest is `2f7b14d861677e84433b6178ddaaa4ad7e9bf1e7a44426c872b083f6f4fadd32`; its exact manifest digest is `1b224481ae39f93497ba4963ed494a54abe2db98e6a0899a28fb611c68a0d7d4`.

The request fingerprint hashes this stream:

1. Domain separator `OMARCHY-PLUGIN-REQUESTS-V1` followed by NUL.
2. Big-endian 64-bit request count.
3. Requests sorted by capability id, required flag, and canonical scope bytes. Each record contains a one-byte required flag, then length-prefixed capability id and canonical scope bytes.

The human reason is intentionally excluded: it carries no authority. Object order, request order, formatting, and reason wording therefore cannot manufacture a permission delta, while required/optional movement or any scope-byte change does. The frozen minimal-fixture request fingerprint is `add469949c66aafff7897dea70e90782f8d61b1e70e1981235d98864ebfac6a3`.

The filesystem reader detects type, mode, and aggregate-size changes encountered during hashing, but it is not an activation transaction. C1 must hash a supervisor-owned staging tree, copy it without following links, make the stored revision immutable, and reverify the digest before atomically publishing the activation record. A mutable publisher checkout is never executable merely because B1 once hashed it.

`identify_tree` reparses the exact `manifest.json` bytes included in the tree and requires that model to equal the caller's model. A caller cannot combine one tree digest with stale or substituted permission requests from another parse.

## Lifecycle state machine

The lifecycle keeps `active` and `pending` records separate. This is the core non-replacement invariant: no validation, grant, candidate-health, or rollback-health failure mutates the active revision.

| Pending state | Accepted transition | Result | Active revision |
|---------------|---------------------|--------|-----------------|
| none | `stage(digest)` | `staged` | unchanged |
| `staged` | validation succeeds with required grants | `candidate` | unchanged |
| `staged` | validation succeeds without required grants | `awaiting_grants` | unchanged |
| `staged` | validation fails | `failed(validation)` | unchanged |
| `awaiting_grants` or `candidate` | grant set becomes complete | `candidate` | unchanged |
| `awaiting_grants` or `candidate` | required grant becomes absent | `awaiting_grants` | unchanged |
| `candidate` | health succeeds | pending becomes `active`; former active is retained | atomically replaced |
| `candidate` | health fails | `failed(health)` | unchanged |
| none with an active revision | begin rollback to a retained previously active revision with required grants | `rollback_candidate` | unchanged |
| `rollback_candidate` | health succeeds | target becomes `active`; former active is retained | atomically replaced |
| `rollback_candidate` | health fails | `failed(rollback_health)` | unchanged |
| `failed` | discard | failed record moves to history | unchanged |

Every other transition throws and leaves the object unchanged. Only a retained revision whose history record shows a successful former `active` state can be a rollback target; a staged, awaiting-grants, candidate, or failed revision is ineligible. Only one pending revision exists at a time, and the currently active digest cannot be restaged.

Lifecycle revision identifiers are exactly 64 lowercase hexadecimal characters, matching the frozen SHA-256 tree identity. Empty, uppercase, short, long, and non-hex identities fail before a state transition.

This is an in-memory contract model, not the C1 persistent transaction. C1 must make the successful candidate or rollback activation plus capability fingerprint and selected-grant binding one durable atomic commit. C2 supplies the authoritative current-grant result; B1 does not infer it from manifest requests.

## Evidence

The focused test validates the strict parser and real fixture tree, duplicate-key and traversal denial, canonical scope bytes, SHA-256 standards and contract goldens, request-order and reason invariance, expanded-scope fingerprint change, executable-mode identity, symlink denial, every successful lifecycle path, invalid transition denial, failed candidate and failed rollback preservation, successful update and rollback, and rejection of a failed revision as a rollback target.

Run from the repository root:

```bash
cmake -S native/plugin-runtime/contracts/manifest -B /tmp/omarchy-plugin-manifest-contract -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/omarchy-plugin-manifest-contract
ctest --test-dir /tmp/omarchy-plugin-manifest-contract --output-on-failure
```

For the sanitizer pass, configure a separate build with `-DPLUGIN_SECURITY_ENABLE_SANITIZERS=ON`. B0 later owns adding this directory to the aggregate native build; B1 deliberately does not edit any root CMake file.
