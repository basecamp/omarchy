#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
rules_dir="$test_tmp/rules.d"
sudo_calls="$test_tmp/sudo-calls"
udevadm_calls="$test_tmp/udevadm-calls"
mkdir -p "$stub_bin" "$rules_dir"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"
exec "$@"
STUB

cat >"$stub_bin/udevadm" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$UDEVADM_CALLS"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/udevadm"

migration="$ROOT/migrations/1786691707.sh"

run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_POWERPROFILES_UDEV_RULES_DIR="$rules_dir" \
    SUDO_CALLS="$sudo_calls" \
    UDEVADM_CALLS="$udevadm_calls" \
    bash -euo pipefail "$migration" >/dev/null
}

touch \
  "$rules_dir/99-power-profile.rules" \
  "$rules_dir/99-omarchy-power-profile.rules" \
  "$rules_dir/99-unrelated.rules"

run_migration

[[ ! -e $rules_dir/99-power-profile.rules ]] ||
  fail "power profile migration removes the pre-package legacy rule"
[[ ! -e $rules_dir/99-omarchy-power-profile.rules ]] ||
  fail "power profile migration removes the retired package rule"
[[ -e $rules_dir/99-unrelated.rules ]] ||
  fail "power profile migration leaves unrelated udev rules alone"
pass "power profile migration removes only retired Omarchy rules"

[[ $(<"$udevadm_calls") == "control --reload" ]] ||
  fail "power profile migration reloads udev without retriggering power events" "$(<"$udevadm_calls")"
pass "power profile migration reloads udev without triggering a profile race"

: >"$sudo_calls"
: >"$udevadm_calls"
run_migration

[[ ! -s $sudo_calls ]] ||
  fail "power profile migration avoids sudo after the machine-wide repair" "$(<"$sudo_calls")"
[[ ! -s $udevadm_calls ]] ||
  fail "power profile migration avoids a redundant udev reload" "$(<"$udevadm_calls")"
pass "power profile migration is a machine-level no-op after repair"
