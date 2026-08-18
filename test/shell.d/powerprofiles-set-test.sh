#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/state"

cat >"$tmp_dir/bin/powerprofilesctl" <<'EOF'
#!/bin/bash

if [[ $1 == "list" ]]; then
  printf '  power-saver:\n* balanced:\n  performance:\n'
elif [[ $1 == "set" ]]; then
  [[ ${POWERPROFILES_SET_FAIL:-0} == "0" ]] || exit 1
  printf '%s\n' "$2" >>"$POWERPROFILES_LOG"
fi
EOF
chmod +x "$tmp_dir/bin/powerprofilesctl"

cat >"$tmp_dir/bin/busctl" <<'EOF'
#!/bin/bash

if [[ ${ON_BATTERY:-0} == "1" ]]; then
  echo "b true"
else
  echo "b false"
fi
EOF
chmod +x "$tmp_dir/bin/busctl"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export POWERPROFILES_LOG="$tmp_dir/calls"
export OMARCHY_POWERPROFILES_STATE_DIR="$tmp_dir/state"

reset_calls_log() {
  : >|"$POWERPROFILES_LOG"
}

reset_calls_log
"$ROOT/bin/omarchy-powerprofiles-set" ac balanced
[[ $(<"$tmp_dir/state/ac") == "balanced" ]] || fail "power profile stores AC preference"
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "balanced" ]] || fail "power profile applies selected AC preference"
pass "power profile stores and applies AC preference"

reset_calls_log
"$ROOT/bin/omarchy-powerprofiles-set" ac
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "balanced" ]] || fail "power profile restores AC preference"
pass "power profile restores AC preference"

if POWERPROFILES_SET_FAIL=1 "$ROOT/bin/omarchy-powerprofiles-set" ac performance; then
  fail "power profile reports a failed selection"
fi
[[ $(<"$tmp_dir/state/ac") == "balanced" ]] || fail "power profile preserves preference after failed selection"
pass "power profile persists only successful selections"

"$ROOT/bin/omarchy-powerprofiles-set" battery performance
[[ $(<"$tmp_dir/state/battery") == "performance" ]] || fail "power profile stores battery preference"
pass "power profile stores battery preference separately"

reset_calls_log
"$ROOT/bin/omarchy-powerprofiles-set" ac
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "balanced" ]] || fail "battery preference does not replace AC preference"
pass "power profile keeps AC and battery preferences separate"

reset_calls_log
ON_BATTERY=1 "$ROOT/bin/omarchy-powerprofiles-set"
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "performance" ]] || fail "autodetect restores battery preference"
pass "power profile autodetect restores battery preference"

rm "$tmp_dir/state/ac"
reset_calls_log
ON_BATTERY=0 "$ROOT/bin/omarchy-powerprofiles-set"
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "performance" ]] || fail "power profile uses performance as AC default"
pass "power profile retains performance as AC default"

"$ROOT/bin/omarchy-powerprofiles-set" ac power-saver
reset_calls_log
"$ROOT/bin/omarchy-powerprofiles-init"
[[ $(tail -n 1 "$POWERPROFILES_LOG") == "power-saver" ]] || fail "init restores the autodetected preference"
pass "power profile init restores the autodetected preference"

rg -F '["omarchy-powerprofiles-set", pendingPowerSource]' "$ROOT/shell/plugins/services/battery/Service.qml" >/dev/null ||
  fail "battery service applies profiles through Omarchy command"
pass "battery service applies profiles through Omarchy command"

rg -F 'omarchy-powerprofiles-set autodetect' "$ROOT/shell/plugins/menu/Menu.qml" >/dev/null ||
  fail "power profile menu persists selections through Omarchy command"
pass "power profile menu persists selections through Omarchy command"
