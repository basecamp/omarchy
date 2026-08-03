#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration=$(grep -rl 'Tighten browser managed-policy directory permissions' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "browser policy permissions migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
sudo_log="$TMPDIR/sudo.log"
mkdir -p "$stub_bin"

# chmod and tee act on the fixture tree so the results can be inspected, and rm
# is recorded and executed so planted entries really disappear. chown is recorded
# but not executed: changing ownership depends on the runner's user and
# privileges, which the test must not rely on.
cat >"$stub_bin/sudo" <<STUB
#!/bin/bash
case \${1:-} in
  chown)
    echo "\$*" >>"$sudo_log"
    exit 0
    ;;
  rm)
    echo "\$*" >>"$sudo_log"
    ;;
esac
exec "\$@"
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
[[ -f $world_writable/color.json && ! -L $world_writable/color.json ]] || fail "migration creates missing color.json"
pass "migration creates missing color.json"
grep -q 'BrowserThemeColor' "$world_writable/color.json" || fail "migration seeds color.json with theme policy"
pass "migration seeds color.json with theme policy"
[[ $(stat -c %a "$world_writable/color.json") == "644" ]] || fail "migration creates color.json with 0644"
pass "migration creates color.json with 0644"
grep -q "chown tester: $world_writable/color.json" "$sudo_log" || fail "migration hands the user ownership of color.json"
pass "migration hands the user ownership of color.json"

# A directory that is already 0755 with a user-owned color.json stays untouched.
already_fixed="$TMPDIR/already-fixed"
mkdir -p "$already_fixed"
chmod 755 "$already_fixed"
echo '{"BrowserThemeColor": "#ff0000", "BrowserColorScheme": "device"}' >"$already_fixed/color.json"
: >"$sudo_log"
policy_dirs="$already_fixed"
run_migration
[[ $(stat -c %a "$already_fixed") == "755" ]] || fail "migration keeps 0755 directory unchanged"
pass "migration keeps 0755 directory unchanged"
grep -q '#ff0000' "$already_fixed/color.json" || fail "migration keeps an existing user-owned color.json"
pass "migration keeps an existing user-owned color.json"
[[ ! -s $sudo_log ]] || fail "migration makes no privileged calls for an already-fixed directory"
pass "migration makes no privileged calls for an already-fixed directory"

# Missing directories (browser never installed) are skipped without error.
policy_dirs="$TMPDIR/does-not-exist"
run_migration
pass "migration skips missing policy directories"

# While the directory was world-writable an attacker could plant a symlink
# named color.json; the migration must replace it instead of following it.
symlinked="$TMPDIR/symlinked"
mkdir -p "$symlinked"
chmod 755 "$symlinked"
ln -s /etc/passwd "$symlinked/color.json"
: >"$sudo_log"
policy_dirs="$symlinked"
run_migration
[[ -f $symlinked/color.json && ! -L $symlinked/color.json ]] || fail "migration replaces a symlinked color.json with a regular file"
pass "migration replaces a symlinked color.json with a regular file"
grep -q 'BrowserThemeColor' "$symlinked/color.json" || fail "migration reseeds a replaced color.json"
pass "migration reseeds a replaced color.json"

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
: >"$sudo_log"
policy_dirs="$root_owned"
STAT_ROOT_OWNER_FOR="$root_owned/color.json" run_migration
grep -q "chown tester: $root_owned/color.json" "$sudo_log" || fail "migration reclaims root-owned color.json for the user"
pass "migration reclaims root-owned color.json for the user"

# Fixing the directory mode only stops future additions; entries planted while
# it was world-writable must be cleaned out. Root-owned administrator policies
# are preserved, anything else that is not color.json is removed.
compromised="$TMPDIR/compromised"
mkdir -p "$compromised"
chmod 755 "$compromised"
echo '{"ExtensionInstallForcelist": ["malicious"]}' >"$compromised/forced-extension.json"
echo '{"HomepageLocation": "https://example.com"}' >"$compromised/admin-policy.json"
echo '{}' >"$compromised/color.json"
cat >"$stub_bin/stat" <<'STUB'
#!/bin/bash
if [[ $1 == "-c" && $2 == "%U" ]]; then
  case $3 in
    */admin-policy.json) echo root ;;
    *) echo attacker ;;
  esac
  exit 0
fi
exec /usr/bin/stat "$@"
STUB
chmod +x "$stub_bin/stat"
: >"$sudo_log"
policy_dirs="$compromised"
run_migration
[[ ! -e $compromised/forced-extension.json ]] || fail "migration removes attacker-planted policy files"
pass "migration removes attacker-planted policy files"
[[ -f $compromised/admin-policy.json ]] || fail "migration preserves root-owned administrator policies"
pass "migration preserves root-owned administrator policies"
[[ -f $compromised/color.json ]] || fail "migration keeps color.json while cleaning planted entries"
pass "migration keeps color.json while cleaning planted entries"
grep -q "rm -rf -- $compromised/forced-extension.json" "$sudo_log" || fail "migration removes planted entries with a privileged rm"
pass "migration removes planted entries with a privileged rm"
