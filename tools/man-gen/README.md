# man-gen

Generates `man/man1/omarchy.1` from `omarchy commands --all --json`.

The output is generated, not hand-written — don't edit `man/man1/omarchy.1` directly, edit this generator instead and regenerate.

## Regenerating

```
omarchy commands --all --json | (cd tools/man-gen && go run . -version "$(cat ../../version)" -out ../../man/man1/omarchy.1)
```

or via the wrapper: `omarchy dev generate-manpage`.

## Group descriptions

`omarchy commands --json` has no group-level metadata (a command's JSON only carries its own group key), so the per-group one-line descriptions used in the `.SS` headings are a hand-maintained copy of `GROUP_DESCRIPTIONS` in `bin/omarchy`. When you add, rename, or remove a group there, update `groupDescriptions` in `main.go` to match — nothing enforces this automatically. A group missing from the map still renders, just with a generic "<Group> commands" fallback heading instead of the real description.

## Verifying output

```
groff -man -ww -z man/man1/omarchy.1   # should print nothing (no warnings)
man ./man/man1/omarchy.1
```
