#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Close the world-writable browser policy directories' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "browser policy permission migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

# The migration elevates to install, move and remove. Run those directly against
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

# -o root -g root cannot be honoured by a test that is not root, and ownership is
# steered by OMARCHY_BROWSER_POLICY_OWNER below rather than by real uids.
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

quarantine="$TMPDIR/quarantine"
fixture=""

new_fixture() {
  fixture="$TMPDIR/root-$1"
  rm -rf "$fixture" "$quarantine"
  mkdir -p "$fixture/etc/chromium/policies/managed" \
    "$fixture/etc/brave/policies/managed" \
    "$fixture/usr/lib/firefox/distribution"
}

# The fixture's directories belong to whoever runs the suite, so that uid stands
# in for root. A case that needs a directory to look foreign passes a different
# one.
owner_uid=$(id -u)

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  : >"$TMPDIR/theme-log"
  PATH="$stub_bin:$PATH" \
    OMARCHY_BROWSER_POLICY_ROOT="$fixture" \
    OMARCHY_BROWSER_POLICY_QUARANTINE="$quarantine" \
    OMARCHY_BROWSER_POLICY_OWNER="${OWNER_OVERRIDE:-$owner_uid}" \
    OMARCHY_PATH="$ROOT" \
    THEME_LOG="$TMPDIR/theme-log" \
    bash -euo pipefail "$migration" >"$TMPDIR/out" 2>&1
}

mode_of() {
  stat -c '%a' "$1"
}

# Where the migration parks a path it moved out of the trust root.
quarantined() {
  echo "$quarantine$1"
}

# A machine as the quattro upgrade left it: world-writable policy directory with
# a color.json an unprivileged theme switch wrote into it.
new_fixture loose
chmod 0777 "$fixture/etc/chromium/policies/managed"
chmod 0777 "$fixture/usr/lib/firefox/distribution"
echo '{"BrowserThemeColor": "#1c2027"}' >"$fixture/etc/chromium/policies/managed/color.json"
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
[[ -e $fixture/usr/lib/firefox/distribution/distribution.ini ]] ||
  fail "migration leaves the browser package's distribution.ini alone"

pass "migration tightens loose browser policy directories and distrusts what was in them"

# A file an ordinary account can still write keeps that account in control of
# administrator policy after the directory is tightened, so reporting it is not
# enough: it has to leave the trust root.
new_fixture planted
chmod 0777 "$fixture/etc/chromium/policies/managed"
echo '{"planted": true}' >"$fixture/etc/chromium/policies/managed/evil.json"
chmod 0666 "$fixture/etc/chromium/policies/managed/evil.json"
# Root's own, and no ordinary account can write it: most likely a real admin
# policy, and deleting that would be its own bug.
echo '{"admin": true}' >"$fixture/etc/chromium/policies/managed/admin.json"
chmod 0644 "$fixture/etc/chromium/policies/managed/admin.json"

run_migration || fail "migration succeeds with planted policy files"

[[ ! -e $fixture/etc/chromium/policies/managed/evil.json ]] ||
  fail "migration removes a writable policy file from the trust root"
[[ -f $(quarantined "$fixture/etc/chromium/policies/managed/evil.json") ]] ||
  fail "migration quarantines the writable policy file rather than deleting it"
grep -q 'Quarantined' "$TMPDIR/out" ||
  fail "migration reports what it quarantined" "got: $(<"$TMPDIR/out")"

[[ -f $fixture/etc/chromium/policies/managed/admin.json ]] ||
  fail "migration leaves a root-owned, unwritable policy file in place"
grep -q 'admin.json' "$TMPDIR/out" ||
  fail "migration reports the policy file it left in place" "got: $(<"$TMPDIR/out")"

pass "migration quarantines policy files an ordinary account can still change"

# stat and chmod both follow a symlink, so a policy directory swapped for a link
# reports the target's mode and would otherwise pass for tight.
new_fixture symlink
elsewhere="$TMPDIR/attacker-dir"
rm -rf "$elsewhere"
mkdir -p "$elsewhere"
chmod 0755 "$elsewhere"
rm -rf "$fixture/etc/chromium/policies/managed"
ln -s "$elsewhere" "$fixture/etc/chromium/policies/managed"

run_migration || fail "migration succeeds where a policy directory is a symlink"

[[ ! -L $fixture/etc/chromium/policies/managed ]] ||
  fail "migration replaces a symlinked policy directory with a real one"
[[ -d $fixture/etc/chromium/policies/managed ]] ||
  fail "migration leaves a real policy directory behind"
[[ $(mode_of "$fixture/etc/chromium/policies/managed") == "755" ]] ||
  fail "migration creates the replacement policy directory 0755"
[[ -d $elsewhere ]] ||
  fail "migration does not follow the link and delete what it pointed at"

pass "migration replaces a symlinked policy directory instead of chmod'ing through it"

# A link to a target that does not exist yet fails [[ -d ]], so nothing but the
# -L check keeps the scan from skipping the path and leaving its owner free to
# create the target later. Nothing else in this fixture is loose, so the scan is
# the only thing that can put the path on the repair list.
new_fixture dangling
rm -rf "$fixture/etc/chromium/policies/managed"
ln -s "$TMPDIR/does-not-exist" "$fixture/etc/chromium/policies/managed"

run_migration || fail "migration succeeds where a policy directory is a dangling symlink"

[[ ! -L $fixture/etc/chromium/policies/managed ]] ||
  fail "migration replaces a dangling symlinked policy directory"
[[ -d $fixture/etc/chromium/policies/managed ]] ||
  fail "migration leaves a real policy directory where a dangling link was"
[[ ! -e $TMPDIR/does-not-exist ]] ||
  fail "migration does not create what the dangling link pointed at"

pass "migration replaces a dangling symlinked policy directory"

# A directory an ordinary account owns can be reopened by that account at any
# time, whatever mode it currently reports.
new_fixture owner
echo '{"planted": true}' >"$fixture/etc/chromium/policies/managed/evil.json"
OWNER_OVERRIDE=$((owner_uid + 1)) run_migration ||
  fail "migration succeeds where the policy directories are not root's"

[[ -d $fixture/etc/chromium/policies/managed ]] ||
  fail "migration leaves a policy directory behind after quarantining a foreign one"
[[ ! -e $fixture/etc/chromium/policies/managed/evil.json ]] ||
  fail "migration carries the contents of a foreign policy directory out of the trust root"
[[ -e $(quarantined "$fixture/etc/chromium") ]] ||
  fail "migration quarantines the foreign directory"

pass "migration quarantines a policy directory an ordinary account owns"

# An account that could write the distribution directory could equally have
# deleted the policy Omarchy ships, so restoration cannot key on the file still
# being there.
new_fixture deleted
chmod 0777 "$fixture/usr/lib/firefox/distribution"
rm -f "$fixture/usr/lib/firefox/distribution/policies.json"

run_migration || fail "migration succeeds where policies.json was deleted"

cmp -s "$ROOT/default/firefox/policies.json" "$fixture/usr/lib/firefox/distribution/policies.json" ||
  fail "migration restores a policies.json that was deleted while the directory was writable"

pass "migration restores a deleted firefox policy"

# A distribution directory Omarchy never opened belongs to the browser package.
# Repairing chromium is no reason to start managing someone else's Firefox.
new_fixture untouched
chmod 0777 "$fixture/etc/chromium/policies/managed"
rm -f "$fixture/usr/lib/firefox/distribution/policies.json"

run_migration || fail "migration succeeds with a pristine distribution directory"

[[ ! -e $fixture/usr/lib/firefox/distribution/policies.json ]] ||
  fail "migration leaves a distribution directory it did not have to repair alone"

pass "migration does not install a policy into a distribution directory it never opened"

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
