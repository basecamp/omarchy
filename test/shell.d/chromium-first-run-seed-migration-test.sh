#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

migration="$ROOT/migrations/1787691200.sh"
seed='{"distribution":{"require_eula":false},"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'
stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

# The scenarios below retarget the one path assignment in the migration. A
# second copy of the literal would escape that rewrite and reach the host.
occurrences=$(grep -Fc '/usr/lib/chromium/initial_preferences' "$migration") || occurrences=0
(( occurrences == 1 )) ||
  fail "Chromium seed migration names its destination exactly once" "found $occurrences occurrences"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"${CALL_LOG:?}"
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

run_migration() {
  local scenario=$1
  local prefs="$test_dir/$scenario/usr/lib/chromium/initial_preferences"

  : >"$test_dir/$scenario.calls"
  # Keep the privileged production destination fixed in the shipped migration.
  # For this isolated test only, rewrite that one assignment in the input fed to
  # bash so no scenario can touch the host's /usr/lib. Every scenario runs under
  # a hardened umask, the case the explicit modes exist for.
  sed "s|^chromium_prefs=\"/usr/lib/chromium/initial_preferences\"$|chromium_prefs=\"$prefs\"|" "$migration" |
    (umask 077 && CALL_LOG="$test_dir/$scenario.calls" PATH="$stub_bin:$PATH" bash -euo pipefail) >/dev/null
}

mode_of() {
  stat -c '%a' "$1"
}

# A machine already on Quattro has no seed and no directory yet.
run_migration fresh
prefs="$test_dir/fresh/usr/lib/chromium/initial_preferences"
[[ $(<"$prefs") == "$seed" ]] || fail "Chromium seed migration writes the seed" "$(cat "$prefs")"
[[ $(mode_of "$prefs") == "644" ]] ||
  fail "Chromium seed stays readable to the browser user under umask 077" "mode $(mode_of "$prefs")"
[[ $(mode_of "${prefs%/*}") == "755" ]] ||
  fail "Chromium seed directory stays traversable under umask 077" "mode $(mode_of "${prefs%/*}")"
pass "Chromium seed migration writes a seed the browser user can read"

# A second user on the same machine, or a rerun: the seed is readable and
# current, so nothing is written and nobody is asked for a password.
run_migration fresh
[[ ! -s $test_dir/fresh.calls ]] ||
  fail "a seeded machine must not prompt for privileges" "$(cat "$test_dir/fresh.calls")"
pass "Chromium seed migration no-ops once the seed is in place"

# What the old mkdir and tee left behind under umask 077: a root-only directory
# and a seed the user cannot read. The read fails, so the migration rewrites the
# seed, and it must come back readable rather than root-only again.
stale_dir="$test_dir/stale/usr/lib/chromium"
mkdir -p "$stale_dir"
printf '%s\n' '{"distribution":{"require_eula":false}}' >"$stale_dir/initial_preferences"
chmod 000 "$stale_dir/initial_preferences"
chmod 700 "$stale_dir"
run_migration stale
[[ $(<"$stale_dir/initial_preferences") == "$seed" ]] ||
  fail "Chromium seed migration replaces a stale seed" "$(cat "$stale_dir/initial_preferences")"
[[ $(mode_of "$stale_dir/initial_preferences") == "644" ]] ||
  fail "a root-only seed comes back readable" "mode $(mode_of "$stale_dir/initial_preferences")"
[[ $(mode_of "$stale_dir") == "755" ]] ||
  fail "a root-only seed directory comes back traversable" "mode $(mode_of "$stale_dir")"
pass "Chromium seed migration repairs a seed the old write left root-only"
