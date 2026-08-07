#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Keep non-Latin keyboard layouts out of the initramfs' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "non-Latin initramfs layout migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# The migration shells out to sudo (to edit the hooks conf) and rebuilds the UKI
# through limine-mkinitcpio. Stub both so the test never touches the real system
# or the real initramfs, and record the rebuild so cases can assert on it.
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/limine-mkinitcpio" <<'STUB'
#!/bin/bash
: >"$REBUILT_MARKER"
STUB

# The migration only rebuilds when limine-mkinitcpio is present, which it is
# here because of the stub above.
cat >"$stub_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/limine-mkinitcpio" "$stub_bin/omarchy-cmd-present"

marker="$TMPDIR/rebuilt"

hooks_with_bundling() {
  local conf="$1"

  cat >"$conf" <<'CONF'
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
FILES+=(/etc/vconsole.conf)
CONF
}

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  local description="$1" vconsole="$2" hooks="$3"

  rm -f "$marker"
  PATH="$stub_bin:$PATH" REBUILT_MARKER="$marker" \
    OMARCHY_VCONSOLE_CONF="$vconsole" OMARCHY_MKINITCPIO_HOOKS_CONF="$hooks" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean: $description"
}

bundling_dropped() {
  ! grep -qx 'FILES+=(/etc/vconsole.conf)' "$1"
}

# A Cyrillic layout can't type a Latin passphrase, so the bundling has to go and
# the UKI has to be rebuilt.
vconsole="$TMPDIR/cyrillic.conf"
hooks="$TMPDIR/cyrillic-hooks.conf"
printf 'KEYMAP=ru\nXKBLAYOUT=ru\n' >"$vconsole"
hooks_with_bundling "$hooks"
run_migration "non-Latin layout" "$vconsole" "$hooks"
bundling_dropped "$hooks" || fail "migration drops bundling for a non-Latin layout"
[[ -f $marker ]] || fail "migration rebuilds the UKI for a non-Latin layout"
pass "migration drops bundling and rebuilds for a non-Latin layout"

# The first entry decides it: us,ru types Latin, so the bundling stays.
vconsole="$TMPDIR/variant.conf"
hooks="$TMPDIR/variant-hooks.conf"
printf 'KEYMAP=us\nXKBLAYOUT="us,ru"\n' >"$vconsole"
hooks_with_bundling "$hooks"
run_migration "keymap variant" "$vconsole" "$hooks"
bundling_dropped "$hooks" && fail "migration keeps bundling when the primary layout is Latin"
pass "migration reads only the primary layout of a comma-separated list"

vconsole="$TMPDIR/latin.conf"
hooks="$TMPDIR/latin-hooks.conf"
printf 'KEYMAP=de\nXKBLAYOUT=de\n' >"$vconsole"
hooks_with_bundling "$hooks"
run_migration "Latin layout" "$vconsole" "$hooks"
bundling_dropped "$hooks" && fail "migration keeps bundling for a Latin layout"
[[ -f $marker ]] && fail "migration skips the rebuild for a Latin layout"
pass "migration leaves a Latin layout alone"

# vconsole.conf only guarantees KEYMAP. XKBLAYOUT went unbound under `set -u`
# here and took every migration behind this one down with it (#6539).
vconsole="$TMPDIR/no-layout.conf"
hooks="$TMPDIR/no-layout-hooks.conf"
printf 'FONT=lat9w-16\nKEYMAP=us\n' >"$vconsole"
hooks_with_bundling "$hooks"
run_migration "vconsole.conf without XKBLAYOUT" "$vconsole" "$hooks"
bundling_dropped "$hooks" && fail "migration keeps bundling when no layout is configured"
pass "migration survives a vconsole.conf that sets no XKBLAYOUT"

# Same failure one branch over: sourcing a file that isn't there fails too.
hooks="$TMPDIR/absent-hooks.conf"
hooks_with_bundling "$hooks"
run_migration "missing vconsole.conf" "$TMPDIR/absent-vconsole.conf" "$hooks"
bundling_dropped "$hooks" && fail "migration keeps bundling when vconsole.conf is missing"
pass "migration survives a missing vconsole.conf"

# Nothing to edit, and running twice must stay clean.
vconsole="$TMPDIR/cyrillic.conf"
hooks="$TMPDIR/no-hooks.conf"
run_migration "missing hooks conf" "$vconsole" "$hooks"
run_migration "missing hooks conf again" "$vconsole" "$hooks"
pass "migration no-ops when the hooks conf is absent"

# Already migrated: the bundling line is gone, so there is nothing to rebuild for.
hooks="$TMPDIR/already-hooks.conf"
printf 'HOOKS=(base udev plymouth)\n' >"$hooks"
run_migration "already applied" "$vconsole" "$hooks"
[[ -f $marker ]] && fail "migration skips the rebuild when bundling is already gone"
pass "migration no-ops when bundling was already removed"
