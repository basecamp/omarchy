#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log="$test_tmp/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-audio-output-sink" <<'STUB'
#!/bin/bash
printf 'stub_sink\n'
STUB
chmod +x "$stub_bin/omarchy-audio-output-sink"

# Reports whatever level the case under test asked for, so no real sink is touched.
cat >"$stub_bin/pactl" <<'STUB'
#!/bin/bash
case "$1" in
  get-sink-volume) printf 'Volume: front-left: 0 / %s%% / 0.00 dB\n' "${STUB_PERCENT:-50}" ;;
  get-sink-mute) printf 'Mute: %s\n' "${STUB_MUTED:-no}" ;;
esac
STUB
chmod +x "$stub_bin/pactl"

cat >"$stub_bin/omarchy-osd" <<'STUB'
#!/bin/bash
printf 'omarchy-osd %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$stub_bin/omarchy-osd"

# +0 leaves the level alone, so each case exercises the read-back and the icon
# choice without moving the volume.
icon_for_percent() {
  : >"$log"
  STUB_PERCENT="$1" \
    STUB_MUTED="${2:-no}" \
    TEST_LOG="$log" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-audio-output-volume" +0 >/dev/null

  sed -n 's/.*-i \([^ ]*\).*/\1/p' "$log"
}

assert_icon() {
  local percent="$1" expected="$2" muted="${3:-no}" actual

  actual=$(icon_for_percent "$percent" "$muted")

  if [[ $actual == $expected ]]; then
    pass "volume $percent% muted=$muted shows $expected"
  else
    fail "volume $percent% muted=$muted shows $expected" \
      "expected: $expected
actual:   $actual"
  fi
}

assert_icon 0 volume-muted
assert_icon 50 volume-muted yes

# Bands come from omarchy-audio-output-switch, which already maps level to icon
# name. They also equal the 0.34/0.67 cutoffs outputIcon() uses for the bar in
# shell/plugins/panels/audio/Panel.qml.
assert_icon 1 volume-low
assert_icon 33 volume-low
assert_icon 34 volume-medium
assert_icon 66 volume-medium
assert_icon 67 volume-high
assert_icon 100 volume-high
