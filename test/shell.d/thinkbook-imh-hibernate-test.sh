#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fix="$ROOT/install/hardware/lenovo/fix-thinkbook-imh-hibernate.sh"
migration="$ROOT/migrations/1787560538.sh"

grep -Fq 'omarchy-hw-match "ThinkBook X IMH"' "$fix" ||
  fail "the fix is gated on ThinkBook X IMH hardware"
grep -Fq 'HibernateMode=shutdown' "$fix" ||
  fail "the fix installs HibernateMode=shutdown"
grep -Fq '/hardware/lenovo/fix-thinkbook-imh-hibernate.sh' \
  "$ROOT/install/hardware/all.sh" ||
  fail "the fix is wired into install/hardware/all.sh"
pass "fresh installs write HibernateMode=shutdown on ThinkBook X IMH"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
conf_dir="$test_tmp/etc/systemd/sleep.conf.d"
calls="$test_tmp/calls"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

echo "$1" >>"$CALLS"

if [[ $1 == mkdir ]]; then
  mkdir -p "$CONF_DIR"
elif [[ $1 == tee ]]; then
  cat >"$CONF_DIR/hibernatemode.conf"
fi
SH
chmod +x "$stub_bin/sudo"

run_migration() {
  (cd "$test_tmp" &&
    PATH="$stub_bin:$PATH" CONF_DIR="$conf_dir" CALLS="$calls" \
    OMARCHY_HIBERNATE_MODE_CONF="$conf_dir/hibernatemode.conf" \
    bash "$migration")
}

# Other hardware: migration is a no-op and writes nothing.
cat >"$stub_bin/omarchy-hw-match" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/omarchy-hw-match"
run_migration >/dev/null
[[ ! -e $conf_dir/hibernatemode.conf ]] ||
  fail "the migration skips machines that are not a ThinkBook X IMH"
pass "the migration skips other hardware"

# ThinkBook X IMH: the migration writes the drop-in.
cat >"$stub_bin/omarchy-hw-match" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-hw-match"
run_migration >/dev/null
grep -qx 'HibernateMode=shutdown' "$conf_dir/hibernatemode.conf" ||
  fail "the migration writes HibernateMode=shutdown for ThinkBook X IMH"
pass "the migration writes HibernateMode=shutdown for ThinkBook X IMH"

# Re-running stays idempotent: no sudo call at all once the drop-in is in
# place, not merely the same bytes written again.
before=$(<"$conf_dir/hibernatemode.conf")
: >"$calls"
run_migration >/dev/null
[[ $(<"$conf_dir/hibernatemode.conf") == "$before" ]] ||
  fail "the migration is idempotent when run twice"
[[ ! -s $calls ]] || fail "an already-configured install is left untouched" "$(cat "$calls")"
pass "re-running the migration changes nothing"
