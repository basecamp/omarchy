#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration=$(grep -rl 'Tighten browser managed-policy directory permissions' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "browser policy permissions migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

# The migration shells out to sudo for chmod/chown/tee. Execute the command
# directly so the fixture tree shows what the real system would see.
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

# Runs the migration the same way omarchy-migrate does, against fixture dirs.
run_migration() {
  USER=tester PATH="$stub_bin:$PATH" OMARCHY_BROWSER_POLICY_DIRS="$policy_dirs" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean"
}

# A world-writable policy directory is restored to 0755 and gains a user-owned
# color.json so theme updates keep working.
world_writable="$TMPDIR/world-writable"
mkdir -p "$world_writable"
chmod 777 "$world_writable"
policy_dirs="$world_writable"
run_migration
[[ $(stat -c %a "$world_writable") == "755" ]] || fail "migration restores 0755 on world-writable policy directory"
pass "migration restores 0755 on world-writable policy directory"
[[ -f $world_writable/color.json ]] || fail "migration creates missing color.json"
pass "migration creates missing color.json"
grep -q 'BrowserThemeColor' "$world_writable/color.json" || fail "migration seeds color.json with theme policy"
pass "migration seeds color.json with theme policy"

# A directory that is already 0755 with a user-owned color.json stays untouched.
already_fixed="$TMPDIR/already-fixed"
mkdir -p "$already_fixed"
chmod 755 "$already_fixed"
echo '{"BrowserThemeColor": "#ff0000", "BrowserColorScheme": "device"}' >"$already_fixed/color.json"
policy_dirs="$already_fixed"
run_migration
[[ $(stat -c %a "$already_fixed") == "755" ]] || fail "migration keeps 0755 directory unchanged"
pass "migration keeps 0755 directory unchanged"
grep -q '#ff0000' "$already_fixed/color.json" || fail "migration keeps an existing user-owned color.json"
pass "migration keeps an existing user-owned color.json"

# Missing directories (browser never installed) are skipped without error.
policy_dirs="$TMPDIR/does-not-exist"
run_migration
pass "migration skips missing policy directories"

# The root-owned repair branch: report the fixture color.json as root-owned and
# expect a chown to the current user.
root_owned="$TMPDIR/root-owned"
mkdir -p "$root_owned"
chmod 755 "$root_owned"
echo '{}' >"$root_owned/color.json"
cat >"$stub_bin/stat" <<'STUB'
#!/bin/bash
if [[ $1 == "-c" && $2 == "%U" && $3 == "$STAT_ROOT_OWNER_FOR" ]]; then
  echo root
  exit 0
fi
exec /usr/bin/stat "$@"
STUB
chmod +x "$stub_bin/stat"
chown_log="$TMPDIR/chown.log"
cat >"$stub_bin/sudo" <<STUB
#!/bin/bash
if [[ \$1 == chown ]]; then echo "\$*" >>"$chown_log"; fi
exec "\$@"
STUB
chmod +x "$stub_bin/sudo"
policy_dirs="$root_owned"
STAT_ROOT_OWNER_FOR="$root_owned/color.json" run_migration
grep -q "chown tester:" "$chown_log" || fail "migration reclaims root-owned color.json for the user"
pass "migration reclaims root-owned color.json for the user"
