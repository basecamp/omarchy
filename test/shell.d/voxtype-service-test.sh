#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_compositor "Voxtype service test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping Voxtype service test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
status_runs="$TMPDIR/status-runs"
bridge_runs="$TMPDIR/bridge-runs"
stub_bin="$TMPDIR/bin"
config_dir="$TMPDIR/voxtype-service"
mkdir -p "$stub_bin" "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/voxtype-service/shell.qml" "$config_dir/shell.qml"

cat >"$stub_bin/voxtype" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-voxtype-status" <<'SH'
#!/bin/bash
set -euo pipefail

count=0
[[ -f $OMARCHY_VOXTYPE_STATUS_RUNS ]] && read -r count <"$OMARCHY_VOXTYPE_STATUS_RUNS"
count=$((count + 1))
printf '%s\n' "$count" >"$OMARCHY_VOXTYPE_STATUS_RUNS"
printf 'malformed status\n'

if (( count == 1 )); then
  printf '{"alt":"recording"}\n'
  sleep 1.3
  exit 1
fi

printf '{"class":"transcribing"}\n'
sleep 1
SH

cat >"$stub_bin/voxtype-audio-bridge" <<'SH'
#!/bin/bash
set -euo pipefail

count=0
[[ -f $OMARCHY_VOXTYPE_BRIDGE_RUNS ]] && read -r count <"$OMARCHY_VOXTYPE_BRIDGE_RUNS"
printf '%s\n' "$((count + 1))" >"$OMARCHY_VOXTYPE_BRIDGE_RUNS"
printf 'malformed audio\n'
printf '{"peak":0.8}\n'
sleep 0.1
exit 1
SH

chmod +x "$stub_bin/voxtype" "$stub_bin/omarchy-voxtype-status" "$stub_bin/voxtype-audio-bridge"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_VOXTYPE_STATUS_RUNS="$status_runs" \
OMARCHY_VOXTYPE_BRIDGE_RUNS="$bridge_runs" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,180p' "$log" >&2
    fail "Voxtype service quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,180p' "$log" >&2
  fail "Voxtype service test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Voxtype service result:\n' >&2
  jq . "$result" >&2
  printf 'Voxtype service log:\n' >&2
  sed -n '1,180p' "$log" >&2
  fail "Voxtype service behavior"
fi

(( $(<"$status_runs") >= 2 )) || fail "Voxtype status follower restarts after exit"
(( $(<"$bridge_runs") >= 2 )) || fail "Voxtype audio bridge restarts during capture"
bridge_count=$(<"$bridge_runs")
sleep 0.6
(( $(<"$bridge_runs") == bridge_count )) || fail "Voxtype audio bridge stops retrying after capture"
pass "Voxtype service parses streams, resets state, and recovers followers"
