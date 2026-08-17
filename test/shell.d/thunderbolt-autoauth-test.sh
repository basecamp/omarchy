#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hooks_conf="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
install_hook="$ROOT/etc/initcpio/install/thunderbolt_autoauth"
runtime_hook="$ROOT/etc/initcpio/hooks/thunderbolt_autoauth"
migration="$ROOT/migrations/1786961462.sh"

resolved_hooks=$(bash -uc "MODULES=(); FILES=(); XKBLAYOUT=us; source '$hooks_conf'; echo \"\${HOOKS[*]}\"")
[[ $resolved_hooks == *" block thunderbolt_autoauth encrypt "* ]] ||
  fail "Thunderbolt authorization runs immediately before encrypt" "actual: $resolved_hooks"
(( $(grep -o 'thunderbolt_autoauth' <<<"$resolved_hooks" | wc -l) == 1 )) ||
  fail "Thunderbolt authorization appears once in HOOKS" "actual: $resolved_hooks"
pass "Thunderbolt authorization runs once immediately before encrypt"

[[ $(bash -c 'add_runscript() { echo added; }; source "$1"; build' -- "$install_hook") == "added" ]] ||
  fail "Thunderbolt install hook adds its runtime script"
pass "Thunderbolt install hook adds its runtime script"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

devices="$test_tmp/devices"
stub_bin="$test_tmp/bin"
mkdir -p "$devices/domain0" "$devices/0-0" "$devices/0-1" "$devices/0-2" "$stub_bin"
printf '0\n' > "$devices/0-0/authorized"
printf '0\n' > "$devices/0-1/authorized"
printf '1\n' > "$devices/0-2/authorized"

cat > "$stub_bin/sleep" <<'EOF'
#!/bin/bash
echo sleep >> "$TEST_LOG"
EOF
chmod +x "$stub_bin/sleep"

sleep_calls="$test_tmp/sleep.log"
: > "$sleep_calls"
PATH="$stub_bin:$PATH" TEST_LOG="$sleep_calls" OMARCHY_THUNDERBOLT_DEVICES_PATH="$devices" \
  bash -c 'source "$1"; run_hook' -- "$runtime_hook"

[[ $(<"$devices/0-0/authorized") == "0" ]] || fail "runtime hook leaves the host router alone"
[[ $(<"$devices/0-1/authorized") == "1" ]] || fail "runtime hook authorizes an attached device"
[[ $(<"$devices/0-2/authorized") == "1" ]] || fail "runtime hook preserves an authorized device"
pass "runtime hook authorizes only attached unauthorized devices"

empty_devices="$test_tmp/empty-devices"
mkdir -p "$empty_devices"
PATH="$stub_bin:$PATH" TEST_LOG="$sleep_calls" OMARCHY_THUNDERBOLT_DEVICES_PATH="$empty_devices" \
  bash -c 'source "$1"; run_hook' -- "$runtime_hook"
(( $(grep -c '^sleep$' "$sleep_calls") == 1 )) ||
  fail "runtime hook adds no delay without a pending device" "$(cat "$sleep_calls")"
pass "runtime hook adds no delay without a pending device"

calls="$test_tmp/calls.log"
marker="$test_tmp/rebuild-complete"
: > "$calls"

cat > "$stub_bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == "limine-mkinitcpio" ]]
EOF
cat > "$stub_bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
echo limine-mkinitcpio >> "$TEST_LOG"
EOF
cat > "$stub_bin/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
chmod +x "$stub_bin"/*

for _ in 1 2; do
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_THUNDERBOLT_HOOKS_CONF="$hooks_conf" \
    OMARCHY_THUNDERBOLT_INSTALL_HOOK="$install_hook" \
    OMARCHY_THUNDERBOLT_RUNTIME_HOOK="$runtime_hook" \
    OMARCHY_THUNDERBOLT_REBUILD_MARKER="$marker" \
    bash -euo pipefail "$migration" >/dev/null
done

(( $(grep -c '^limine-mkinitcpio$' "$calls") == 1 )) ||
  fail "migration rebuilds the UKI exactly once" "$(cat "$calls")"
[[ -f $marker ]] || fail "migration records the machine-wide rebuild"
pass "migration rebuilds the UKI exactly once"
