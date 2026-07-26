#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Move zram tuning to a vendor drop-in' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "zram drop-in migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# The migration shells out to pacman (ownership check) and sudo (removal).
# Stub both so the test never touches the real system, and let each case pick
# what `pacman -Qo` reports through PACMAN_OWNS.
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ ${PACMAN_OWNS:-0} == 1 ]]
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

chmod +x "$stub_bin/pacman" "$stub_bin/sudo"

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  local conf="$1"
  PATH="$stub_bin:$PATH" OMARCHY_ZRAM_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean for $(basename "$conf")"
}

# archinstall's own output: a [zram0] section with nothing but the algorithm.
conf="$TMPDIR/archinstall.conf"
printf '[zram0]\ncompression-algorithm = zstd\n' >"$conf"
run_migration "$conf"
[[ -f $conf ]] && fail "migration removes archinstall's generated config"
pass "migration removes archinstall's generated config"

# Same shape, different algorithm, plus comments and blank lines.
conf="$TMPDIR/commented.conf"
printf '# written by archinstall\n\n[zram0]\ncompression-algorithm = lz4\n\n' >"$conf"
run_migration "$conf"
[[ -f $conf ]] && fail "migration ignores comments and a non-zstd algorithm"
pass "migration ignores comments and a non-zstd algorithm"

# A config that sets nothing decides nothing, and must not take the migration
# chain down with it.
conf="$TMPDIR/comments-only.conf"
printf '# nothing to see here\n\n' >"$conf"
run_migration "$conf"
[[ -f $conf ]] && fail "migration removes a config that sets nothing"
pass "migration removes a config that sets nothing"

conf="$TMPDIR/empty.conf"
: >"$conf"
run_migration "$conf"
[[ -f $conf ]] && fail "migration removes an empty config"
pass "migration removes an empty config"

# A local override must survive.
conf="$TMPDIR/local.conf"
printf '[zram0]\ncompression-algorithm = zstd\nzram-size = ram / 4\n' >"$conf"
run_migration "$conf"
[[ -f $conf ]] || fail "migration keeps a locally edited config"
pass "migration keeps a locally edited config"

# Package-owned copies go away with their package; the migration must not touch
# them.
conf="$TMPDIR/owned.conf"
printf '[zram0]\ncompression-algorithm = zstd\n' >"$conf"
PATH="$stub_bin:$PATH" PACMAN_OWNS=1 OMARCHY_ZRAM_CONF="$conf" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration exits clean for a package-owned config"
[[ -f $conf ]] || fail "migration keeps a package-owned config"
pass "migration keeps a package-owned config"

# Nothing to do, and running twice must stay clean.
conf="$TMPDIR/absent.conf"
run_migration "$conf"
run_migration "$conf"
pass "migration no-ops when the config is already gone"
