#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin" "$tmp_dir/Videos"

cat >"$stub_bin/gpu-screen-recorder" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_RECORDER_ARGS"
while (($#)); do
  if [[ $1 == "-o" ]]; then
    touch "$2"
    break
  fi
  shift
done
SH

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

printf '%s\n' '[{"focused":true,"width":1920,"height":1080}]'
SH

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

printf '%s\n' "$OMARCHY_TEST_PCI_DEVICES"
SH

for command in omarchy-hyprland-monitor-focused omarchy-shell omarchy-notification-send; do
  cat >"$stub_bin/$command" <<'SH'
#!/bin/bash

[[ ${0##*/} == "omarchy-hyprland-monitor-focused" ]] && echo "eDP-1"
SH
done

chmod +x "$stub_bin"/*

export HOME="$tmp_dir"
export PATH="$stub_bin:$PATH"
export OMARCHY_SCREENRECORD_DIR="$tmp_dir/Videos"
export OMARCHY_TEST_RECORDER_ARGS="$tmp_dir/recorder-args"

run_recorder() {
  rm -f "$OMARCHY_TEST_RECORDER_ARGS" "$tmp_dir"/Videos/*
  OMARCHY_TEST_PCI_DEVICES="$1" "$ROOT/bin/omarchy-capture-screenrecording" --fullscreen
  [[ -f $OMARCHY_TEST_RECORDER_ARGS ]] || fail "$2 did not start the recorder"
}

run_recorder $'0000:00:02.0 0300: 8086:191b (rev 06)\n0000:01:00.0 0300: 1002:67ef (rev c0)' "Baffin detection"
grep -Fx -- "-encoder" "$OMARCHY_TEST_RECORDER_ARGS" >/dev/null &&
  grep -Fx -- "cpu" "$OMARCHY_TEST_RECORDER_ARGS" >/dev/null ||
  fail "Baffin forces CPU encoding"
pass "Baffin forces CPU encoding"

run_recorder "0000:01:00.0 0300: 1002:73df (rev c1)" "unaffected GPU detection"
if grep -Fx -- "-encoder" "$OMARCHY_TEST_RECORDER_ARGS" >/dev/null; then
  fail "unaffected GPUs preserve automatic encoder selection"
fi
pass "unaffected GPUs preserve automatic encoder selection"
