# C0 Trusted Manifest Validation and Discovery

## Result

C0 adds a Qt-free trusted discovery library under `native/plugin-runtime/discovery/`. It composes B1's strict schema-v2 parser and content-identity implementation without loading QML, invoking worker entry points, evaluating shell, or importing any plugin-owned library.

The aggregate native build registers the library directly, while the directory remains independently configurable for focused and sanitizer validation.

## Discovery contract

Discovery accepts one trusted root, a bounded list of supervisor-owned directory-to-tree-SHA-256 pins, and the schema-v2 feature state. It enumerates only immediate children of the root, stops at 1,024 entries, sorts paths before validation, and rejects root or child symlinks, non-directory children, missing/non-regular/oversized manifests, malformed schema-v2 JSON, and every tree that B1 cannot identify.

A schema-v2 tree becomes a `VerifiedPlugin` only when the feature is enabled, its strict manifest parses, B1 re-reads and identifies the complete bounded tree, and the resulting tree digest exactly matches the trusted lowercase SHA-256 pin. The returned manifest and identity therefore come from the same verified tree. C1 remains responsible for creating the supervisor-owned immutable revision and pin; a mutable checkout with a freshly computed digest is validation input, not an executable discovery record.

Duplicate registrations reject the named directory. After validation, every candidate sharing a manifest plugin id is removed rather than selecting a first or path-order winner. Diagnostics contain stable codes, relative directory labels, and bounded parser details, then sort by directory and code for deterministic CLI and test output.

## Compatibility boundary

Schema v2 is disabled unless the caller explicitly enables its feature gate. A valid but disabled v2 tree produces no executable candidate.

Schema-v1 manifests are reported as `legacy_v1_unsafe` and never enter the verified result. The narrow legacy marker exists only to improve the migration diagnostic; no schema-v1 id, path, entry point, permission, or other field is trusted. Ambiguous or escaped spellings fall back to invalid-manifest handling. Existing schema-v1 execution remains the explicitly unsafe compatibility path outside this secure discovery API.

## Evidence

The focused fixture suite proves a known B1 identity golden, disabled-v2 denial, missing and mismatched pin denial, duplicate registration and duplicate plugin-id rejection, legacy-v1 classification, root-child symlink and non-directory rejection, deterministic diagnostics, and discovery of an executable-bit file without executing it.

Run:

```bash
cmake -S native/plugin-runtime/discovery -B /tmp/omarchy-plugin-discovery -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build /tmp/omarchy-plugin-discovery
ctest --test-dir /tmp/omarchy-plugin-discovery --output-on-failure
```

For the sanitizer pass, configure a separate build with `-DPLUGIN_SECURITY_ENABLE_SANITIZERS=ON`. C1 still owns immutable storage and atomic activation; C2 owns grant completeness; D0 owns install, update, enable, rollback, and revoke command integration.
