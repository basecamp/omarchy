#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Close the world-writable browser policy directories' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "browser policy permission migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

# The migration elevates to chmod, remove and install. Run those directly against
# the fixture rather than reaching the real system. Both elevation paths are
# stubbed: the migration picks between them on whether it has a terminal, and
# which one a test run gets is not something to depend on.
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/pkexec" <<'STUB'
#!/bin/bash
exec "$@"
STUB

# -o root -g root cannot be honoured by a test that is not root, and the
# ownership is not what these assertions are about.
cat >"$stub_bin/install" <<'STUB'
#!/bin/bash
args=()
while (($# > 0)); do
  case "$1" in
  -o | -g)
    shift 2
    ;;
  *)
    args+=("$1")
    shift
    ;;
  esac
done
exec /usr/bin/install "${args[@]}"
STUB

cat >"$stub_bin/omarchy-theme-set-browser" <<'STUB'
#!/bin/bash
printf 'called\n' >>"$THEME_LOG"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/pkexec" "$stub_bin/install" "$stub_bin/omarchy-theme-set-browser"

fixture=""

new_fixture() {
  fixture="$TMPDIR/root-$1"
  rm -rf "$fixture"
  mkdir -p "$fixture/etc/chromium/policies/managed" \
    "$fixture/etc/brave/policies/managed" \
    "$fixture/usr/lib/firefox/distribution"
}

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  : >"$TMPDIR/theme-log"
  PATH="$stub_bin:$PATH" \
    OMARCHY_BROWSER_POLICY_ROOT="$fixture" \
    OMARCHY_PATH="$ROOT" \
    THEME_LOG="$TMPDIR/theme-log" \
    bash -euo pipefail "$migration" >"$TMPDIR/out" 2>&1
}

mode_of() {
  stat -c '%a' "$1"
}

# A machine as the quattro upgrade left it: world-writable policy directory with
# a color.json an unprivileged theme switch wrote into it.
new_fixture loose
chmod 0777 "$fixture/etc/chromium/policies/managed"
chmod 0777 "$fixture/usr/lib/firefox/distribution"
echo '{"BrowserThemeColor": "#1c2027"}' >"$fixture/etc/chromium/policies/managed/color.json"
echo '{"planted": true}' >"$fixture/etc/chromium/policies/managed/evil.json"
echo 'tampered' >"$fixture/usr/lib/firefox/distribution/policies.json"
echo 'pkg' >"$fixture/usr/lib/firefox/distribution/distribution.ini"

run_migration || fail "migration succeeds on a world-writable install"

[[ $(mode_of "$fixture/etc/chromium/policies/managed") == "755" ]] ||
  fail "migration tightens the chromium policy directory" "got: $(mode_of "$fixture/etc/chromium/policies/managed")"
[[ $(mode_of "$fixture/usr/lib/firefox/distribution") == "755" ]] ||
  fail "migration tightens the firefox distribution directory" "got: $(mode_of "$fixture/usr/lib/firefox/distribution")"

# color.json sat in a directory anyone could write, so it is dropped rather than
# trusted, and regenerated through the privileged helper.
[[ ! -e $fixture/etc/chromium/policies/managed/color.json ]] ||
  fail "migration drops the untrusted color.json"
[[ -s $TMPDIR/theme-log ]] ||
  fail "migration repaints the browser accent through omarchy-theme-set-browser"

# Omarchy ships the authoritative policies.json, so that one is restored.
cmp -s "$ROOT/default/firefox/policies.json" "$fixture/usr/lib/firefox/distribution/policies.json" ||
  fail "migration restores the shipped firefox policies.json"
[[ $(mode_of "$fixture/usr/lib/firefox/distribution/policies.json") == "644" ]] ||
  fail "migration installs policies.json 0644"

# A file Omarchy did not put there could equally be a real admin policy, so it is
# reported and left alone.
[[ -e $fixture/etc/chromium/policies/managed/evil.json ]] ||
  fail "migration leaves an unrecognized policy file in place"
grep -q 'evil.json' "$TMPDIR/out" ||
  fail "migration reports an unrecognized policy file" "got: $(<"$TMPDIR/out")"
[[ -e $fixture/usr/lib/firefox/distribution/distribution.ini ]] ||
  fail "migration leaves the browser package's distribution.ini alone"

pass "migration tightens loose browser policy directories and distrusts what was in them"

# A writable parent is as good as a writable policy directory, so the whole chain
# the 0777 install could have created is checked.
new_fixture parents
chmod 0777 "$fixture/etc/chromium" "$fixture/etc/chromium/policies"
run_migration || fail "migration succeeds on a world-writable parent chain"

[[ $(mode_of "$fixture/etc/chromium") == "755" ]] ||
  fail "migration tightens /etc/chromium" "got: $(mode_of "$fixture/etc/chromium")"
[[ $(mode_of "$fixture/etc/chromium/policies") == "755" ]] ||
  fail "migration tightens /etc/chromium/policies" "got: $(mode_of "$fixture/etc/chromium/policies")"

pass "migration tightens a world-writable policy parent directory"

# Already repaired, by an earlier run or by another user on the same machine.
# Migrations run once per user, so this has to be a silent no-op that changes
# nothing -- including not dropping a color.json that is now trustworthy.
new_fixture tight
echo 'keep' >"$fixture/etc/chromium/policies/managed/color.json"
run_migration || fail "migration succeeds on an already-tightened install"

[[ $(<"$fixture/etc/chromium/policies/managed/color.json") == "keep" ]] ||
  fail "migration leaves a color.json alone once the directory is not writable"
[[ ! -s $TMPDIR/theme-log ]] ||
  fail "migration does no work when nothing is loose"

pass "migration no-ops once the policy directories are tight"

# Group-writable is not safe either: it is the same grant to a smaller set.
new_fixture group
chmod 0775 "$fixture/etc/brave/policies/managed"
run_migration || fail "migration succeeds on a group-writable directory"
[[ $(mode_of "$fixture/etc/brave/policies/managed") == "755" ]] ||
  fail "migration tightens a group-writable policy directory" "got: $(mode_of "$fixture/etc/brave/policies/managed")"

pass "migration tightens group-writable policy directories too"

# Nothing to repair on a machine with no browser policy directories at all.
new_fixture empty
rm -rf "$fixture"
mkdir -p "$fixture"
run_migration || fail "migration succeeds where no browser policy directory exists"

pass "migration no-ops where no browser policy directory exists"
