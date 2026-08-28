#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

facade="$ROOT/bin/omarchy-app-launch-responsive"
control="$ROOT/bin/omarchy-app-launch-responsive-control"
core="$ROOT/bin/omarchy-app-launch-responsive-core"
assets="$ROOT/default/app-launch-responsive"
config="$assets/config.json"
unit="$assets/omarchy-app-launch-responsive.service"
policy="$assets/org.omarchy.app-launch-responsive.policy"

python3 -m py_compile "$core" "$ROOT/test/shell.d/app-launch-responsive-core-test.py"
python3 -m json.tool "$config" >/dev/null
python3 "$ROOT/test/shell.d/app-launch-responsive-core-test.py"
pass "responsive app-launch core gates, transitions, ownership, and rollback"

grep -Fq 'Reduce slow app-launch latency' "$facade" ||
  fail "facade is framed around slow app-launch latency"
grep -Fq 'probe --json' "$facade" ||
  fail "facade cannot report exact hardware support before setup"
grep -Fq 'audit-config --json "$source_dir/config.json" --require-stock' "$control" ||
  fail "first enable lacks an exact live-stock preflight"

audit_line=$(grep -nF 'audit-config --json "$source_dir/config.json" --require-stock' "$control" | cut -d: -f1)
first_install_line=$(grep -nF '  install_templates' "$control" | tail -1 | cut -d: -f1)
((audit_line < first_install_line)) ||
  fail "first setup mutates the system before its stock preflight"
pass "first toggle probes support and stock before setup mutations"

grep -Fq 'exec 9>/run/lock/omarchy-app-launch-responsive.lock' "$control" ||
  fail "privileged setup and preference changes have no fixed serialization lock"
grep -Fq 'flock -x 9' "$control" || fail "privileged control lock is not exclusive"
pass "privileged control operations are serialized"

stop_line=$(grep -nF 'systemctl disable --now "$service"' "$control" | head -1 | cut -d: -f1)
inactive_line=$(grep -nF 'if service_active' "$control" | head -1 | cut -d: -f1)
verify_line=$(grep -nF '"$core" verify-removable --json' "$control" | head -1 | cut -d: -f1)
delete_line=$(grep -nF 'rm -f -- "$policy" "$unit" "$config"' "$control" | cut -d: -f1)
((stop_line < inactive_line && inactive_line < verify_line && verify_line < delete_line)) ||
  fail "setup rollback deletes files before stop and clean-ownership verification"
grep -Fq '[[ ! -e $wants && ! -L $wants ]]' "$control" ||
  fail "setup rollback ignores the systemd wants symlink"
pass "incomplete setup rollback proves stop, ownership, and wants cleanup before deletion"

grep -Fq 'setup_complete=true' "$control" || fail "first apply is outside the setup transaction"
grep -Fq 'complete backend was retained OFF' "$control" ||
  fail "clean first-apply failure does not retain a complete OFF backend"
pass "failed first apply retains either a complete OFF backend or its recovery watcher"

mapfile -t writable < <(sed -n 's/^ReadWritePaths=//p' "$unit" | sort)
mapfile -t expected < <(
  {
    printf '%s\n' \
      /run/omarchy-app-launch-responsive \
      /var/lib/omarchy-app-launch-responsive \
      /sys/module/processor_thermal_soc_slider/parameters/slider_balance \
      /sys/module/processor_thermal_soc_slider/parameters/slider_offset
    jq -r '.hardware.epp_paths[], .hardware.platform_profile_realpaths[]' "$config"
  } | sort
)
[[ ${writable[*]} == "${expected[*]}" ]] ||
  fail "systemd write allowlist differs from the exact configured paths"
grep -Fxq 'ProtectSystem=strict' "$unit" || fail "service lacks ProtectSystem=strict"
grep -Fxq 'ProtectKernelTunables=yes' "$unit" || fail "service lacks ProtectKernelTunables=yes"
grep -Fxq 'CapabilityBoundingSet=' "$unit" || fail "service retains Linux capabilities"
pass "root service can write only its exact state and tuned sysfs paths"

grep -Fq '<allow_active>yes</allow_active>' "$policy" ||
  fail "installed set toggle is not available to the active local user"
grep -Fq '<allow_inactive>no</allow_inactive>' "$policy" ||
  fail "inactive sessions can invoke the privileged control helper"
grep -Fq '/usr/bin/omarchy-app-launch-responsive-control' "$policy" ||
  fail "Polkit policy is not pinned to the fixed control helper"
pass "Polkit grants only the fixed active-session helper actions"

for forbidden in bios_version kernel_release microcode package_version srcversion vermagic sha256 power_supply_inventory; do
  ! grep -Fq "$forbidden" "$config" || fail "config pins volatile field: $forbidden"
done
pass "config has no volatile software-version or power-supply inventory pins"
