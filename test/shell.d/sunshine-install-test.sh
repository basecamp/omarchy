#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
log="$test_tmp/calls.log"
systemctl_log="$test_tmp/systemctl.log"
enabled_flag="$test_tmp/sunshine-enabled"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
printf 'cmd-missing:%s\n' "$*" >>"$OMARCHY_TEST_LOG"

if [[ $1 == "ufw" && ${OMARCHY_TEST_UFW:-} == "1" ]]; then
  exit 1
fi

exit 0
SH

cat >"$mock_bin/omarchy-webapp-install" <<'SH'
#!/bin/bash
printf 'webapp-install:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf 'webapp-launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/ufw" <<'SH'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/ip" <<'SH'
#!/bin/bash
printf 'ip %s\n' "$*" >>"$OMARCHY_TEST_LOG"
exit 1
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_SYSTEMCTL_LOG"

action=""
unit=""
for arg in "$@"; do
  case $arg in
    --user|--now|--quiet)
      ;;
    enable|disable|start|stop|is-enabled|is-active)
      action=$arg
      ;;
    -*)
      ;;
    *)
      unit=$arg
      ;;
  esac
done

[[ $unit == "sunshine" ]] && unit=sunshine.service

canonical=app-dev.lizardbyte.app.Sunshine.service

if [[ $action == "is-enabled" ]]; then
  if [[ $unit == "sunshine.service" || $unit == $canonical ]]; then
    if [[ -f $OMARCHY_TEST_SUNSHINE_ENABLED ]]; then
      exit 0
    fi
  fi
  exit 1
fi

if [[ $action == "enable" ]]; then
  if [[ $unit == $canonical ]]; then
    printf '1\n' >"$OMARCHY_TEST_SUNSHINE_ENABLED"
    exit 0
  fi

  if [[ $unit == "sunshine.service" ]]; then
    if [[ -f $OMARCHY_TEST_SUNSHINE_ENABLED ]]; then
      exit 0
    fi

    printf 'Failed to enable unit: Unit sunshine.service does not exist\n' >&2
    exit 1
  fi
fi

exit 0
SH

chmod +x "$mock_bin"/*

run_install() {
  HOME="$test_home" \
  PATH="$mock_bin:$PATH" \
  OMARCHY_TEST_LOG="$log" \
  OMARCHY_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  OMARCHY_TEST_SUNSHINE_ENABLED="$enabled_flag" \
  OMARCHY_TEST_UFW="${OMARCHY_TEST_UFW:-}" \
    "$ROOT/bin/omarchy-install-service-sunshine"
}

wait_for_log() {
  local pattern="$1"
  local file="$2"
  local attempt

  for attempt in {1..50}; do
    grep -q -- "$pattern" "$file" && return 0
    sleep 0.05
  done

  return 1
}

: >"$log"
: >"$systemctl_log"
rm -f "$enabled_flag"

output=$(run_install)

grep -Fxq 'pkg-add:sunshine' "$log" || fail "sunshine install adds the sunshine package" "$output"
grep -Fq 'enable --now app-dev.lizardbyte.app.Sunshine.service' "$systemctl_log" ||
  fail "sunshine install enables the canonical Arch unit" "$(cat "$systemctl_log")"
grep -E 'enable --now sunshine([.]service)?$' "$systemctl_log" &&
  fail "sunshine install must not enable the alias before the canonical unit exists" "$(cat "$systemctl_log")"
grep -Fxq 'cmd-missing:ufw' "$log" || fail "sunshine install still checks the firewall after enable" "$output"
grep -Fq 'UFW is not installed; skipping Sunshine firewall rules.' <<<"$output" ||
  fail "sunshine install skips ufw when it is missing" "$output"
grep -Fq 'webapp-install:Sunshine Admin' "$log" ||
  fail "sunshine install still installs the admin webapp after enable" "$log"
wait_for_log 'webapp-launch:https://localhost:47990' "$log" ||
  fail "sunshine install still launches the admin webapp after enable" "$log"
grep -Fxq 'o.launch_on_start("sunshine")' "$test_home/.config/hypr/autostart.lua" ||
  fail "sunshine install still enables hyprland autostart after enable"
pass "fresh sunshine install enables the canonical unit and continues"

: >"$log"
: >"$systemctl_log"
OMARCHY_TEST_UFW=1 output=$(run_install)

grep -Fq 'enable --now sunshine' "$systemctl_log" ||
  fail "already-enabled sunshine.service is reused via its alias" "$(cat "$systemctl_log")"
grep -Fq 'sudo ufw allow' "$log" || fail "sunshine install still opens firewall ports after enable" "$log"
grep -Fq 'webapp-install:Sunshine Admin' "$log" ||
  fail "re-running sunshine install still installs the admin webapp" "$log"
autostart_count=$(grep -cFx 'o.launch_on_start("sunshine")' "$test_home/.config/hypr/autostart.lua")
(( autostart_count == 1 )) || fail "sunshine autostart stays a single line on reinstall"
pass "already-enabled sunshine.service is idempotent and later steps still run"
