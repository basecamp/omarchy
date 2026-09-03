#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home="$test_tmp/home"
log="$test_tmp/systemctl.log"
mkdir -p "$stub_bin" "$home/.config/hypr"

# Fresh install: sunshine.service alias does not exist until the real unit is
# enabled. Enabling by the alias must fail; enabling by the package unit works.
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_SYSTEMCTL_LOG"
if [[ ${1:-} == "--user" && ${2:-} == "enable" && ${3:-} == "--now" ]]; then
  unit=${4:-}
  case "$unit" in
    app-dev.lizardbyte.app.Sunshine.service)
      exit 0
      ;;
    sunshine|sunshine.service)
      echo "Failed to enable unit: Unit sunshine.service does not exist" >&2
      exit 1
      ;;
    *)
      echo "unexpected unit: $unit" >&2
      exit 1
      ;;
  esac
fi
exit 0
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
# Report ufw missing so install skips firewall work in this fixture.
[[ $1 == ufw ]]
SH

cat >"$stub_bin/omarchy-webapp-install" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

: >"$log"
HOME="$home" PATH="$stub_bin:$PATH" TEST_SYSTEMCTL_LOG="$log" \
  bash "$ROOT/bin/omarchy-install-service-sunshine" >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "sunshine install succeeds when enabling the real unit" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"

grep -F 'enable --now app-dev.lizardbyte.app.Sunshine.service' "$log" >/dev/null ||
  fail "sunshine install enables the package unit name" "$(cat "$log")"
if grep -E 'enable --now sunshine(\.service)?$' "$log" >/dev/null; then
  fail "sunshine install must not enable by the unrealized alias" "$(cat "$log")"
fi
pass "sunshine install enables app-dev.lizardbyte.app.Sunshine.service"

grep -F 'o.launch_on_start("sunshine")' "$home/.config/hypr/autostart.lua" >/dev/null ||
  fail "sunshine install adds hyprland autostart" "$(cat "$home/.config/hypr/autostart.lua" 2>/dev/null)"
pass "sunshine install completes past enable into autostart"

# Source-level guard: install script documents and uses the real unit constant.
grep -F 'SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"' \
  "$ROOT/bin/omarchy-install-service-sunshine" >/dev/null ||
  fail "install script defines SUNSHINE_UNIT"
grep -F 'enable --now "$SUNSHINE_UNIT"' "$ROOT/bin/omarchy-install-service-sunshine" >/dev/null ||
  fail "install script enables via SUNSHINE_UNIT"
pass "install script sources the real Sunshine unit name"
