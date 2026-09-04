#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
hyprctl_log="$test_tmp/hyprctl.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "clients" ]]; then
  printf '%s\n' "$OMARCHY_TEST_CLIENTS_JSON"
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
SH
chmod +x "$mock_bin/hyprctl"

run_restore() {
  : >"$hyprctl_log"
  PATH="$mock_bin:$PATH" HYPRCTL_LOG="$hyprctl_log" \
    OMARCHY_TEST_CLIENTS_JSON="$1" \
    bash "$ROOT/bin/omarchy-hyprland-window-restore-presentation"
}

run_restore '[]'
[[ ! -s $hyprctl_log ]] || fail "restore is a no-op when no presentation terminal exists" "$(cat "$hyprctl_log")"
pass "restore is a no-op when no presentation terminal exists"

run_restore '[{"address":"0xabc","class":"org.omarchy.terminal","initialClass":"org.omarchy.terminal"}]'
expected="$test_tmp/expected.log"
cat >"$expected" <<'EOF'
dispatch hl.dsp.window.float({ window = "address:0xabc", action = "on" })
dispatch hl.dsp.window.resize({ window = "address:0xabc", x = 875, y = 600 })
dispatch hl.dsp.window.center({ window = "address:0xabc" })
dispatch hl.dsp.focus({ window = "address:0xabc" })
EOF
diff -u "$expected" "$hyprctl_log" || fail "restore re-applies float, size, center, and focus" "$(diff -u "$expected" "$hyprctl_log")"
pass "restore re-applies float, size, center, and focus"

run_restore '[{"address":"0xdef","class":"foot","initialClass":"org.omarchy.terminal"}]'
grep -F 'window = "address:0xdef"' "$hyprctl_log" >/dev/null || fail "restore matches initialClass"
pass "restore matches presentation terminals by initialClass"

run_restore '[{"address":"0xfoot","class":"foot","initialClass":"foot"}]'
[[ ! -s $hyprctl_log ]] || fail "restore ignores ordinary terminals" "$(cat "$hyprctl_log")"
pass "restore ignores ordinary terminals"
