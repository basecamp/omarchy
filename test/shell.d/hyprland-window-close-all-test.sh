#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
hyprctl_log="$test_tmp/hyprctl.log"
clients_log="$test_tmp/clients-calls.log"
mkdir -p "$mock_bin"

# The mock empties the client list once it has been polled a few times, so the
# --wait path observes windows disappearing; the poll count in CLIENTS_CALLS_LOG
# proves the wait actually ran. Use a marker file to change behavior between
# cases: "empty" makes the list disappear after the given number of calls,
# "sticky" never empties it (for the timeout-bounded case).
cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "clients" ]]; then
  echo x >>"$CLIENTS_CALLS_LOG"
  calls=$(wc -l <"$CLIENTS_CALLS_LOG")
  empty_after=${CLIENTS_EMPTY_AFTER:-0}
  if (( empty_after == 0 || calls < empty_after )); then
    printf '[{"address":"0xabc"},{"address":"0xdef"}]\n'
  else
    printf '[]\n'
  fi
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
SH
chmod +x "$mock_bin/hyprctl"

run_close_all() {
  PATH="$mock_bin:$PATH" \
  HYPRCTL_LOG="$hyprctl_log" \
  CLIENTS_CALLS_LOG="$clients_log" \
  CLIENTS_EMPTY_AFTER="${1:-0}" \
  OMARCHY_CLOSE_ALL_TIMEOUT="${2:-10}" \
    "$ROOT/bin/omarchy-hyprland-window-close-all" "${3:-}"
}

expected_dispatch() {
  cat >"$test_tmp/expected.log" <<'EOF'
dispatch hl.dsp.window.close({ window = "address:0xabc" })
dispatch hl.dsp.window.close({ window = "address:0xdef" })
dispatch hl.dsp.focus({ workspace = "1" })
EOF
}

# --- Plain path (keybind): close requests only, no waiting -----------------
: >"$hyprctl_log"
: >"$clients_log"
run_close_all 0 10
expected_dispatch
diff -u "$test_tmp/expected.log" "$hyprctl_log" || fail "close-all targets each window with the Lua dispatcher"
pass "close-all targets each window with the Lua dispatcher"
[[ $(wc -l <"$clients_log") == 1 ]] || fail "plain close-all does not wait for windows to exit"
pass "plain close-all does not wait for windows to exit"

# --- --wait path: polls until the client list empties ----------------------
: >"$hyprctl_log"
: >"$clients_log"
run_close_all 4 10 --wait
expected_dispatch
diff -u "$test_tmp/expected.log" "$hyprctl_log" || fail "--wait still targets each window with the Lua dispatcher"
pass "--wait still targets each window with the Lua dispatcher"
[[ $(wc -l <"$clients_log") -ge 3 ]] || fail "--wait polls until windows have exited"
pass "--wait polls until windows have exited"

# --- --wait path with a window that never closes: bounded by the timeout ----
: >"$hyprctl_log"
: >"$clients_log"
if run_close_all 0 1 --wait; then
  pass "--wait with a stuck window still completes within the timeout"
else
  fail "--wait with a stuck window still completes within the timeout"
fi
