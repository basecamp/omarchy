#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/state/omarchy"

printf '150\n' >"$test_tmp/state/omarchy/audio-max-volume"
printf '148\n' >"$test_tmp/volume"

cat >"$test_tmp/bin/omarchy-audio-output-sink" <<'SH'
#!/bin/bash
echo test_sink
SH

cat >"$test_tmp/bin/pactl" <<'SH'
#!/bin/bash
case "$1 $2" in
  "get-sink-volume test_sink") printf 'Volume: front-left: 65536 / %s%%\n' "$(cat "$TEST_TMP/volume")" ;;
  "get-sink-mute test_sink") echo 'Mute: no' ;;
  "set-sink-mute test_sink") ;;
  "set-sink-volume test_sink") printf '%s\n' "${3%%%}" >"$TEST_TMP/volume" ;;
  *) exit 1 ;;
esac
SH

cat >"$test_tmp/bin/omarchy-osd" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_TMP/osd"
SH

chmod +x "$test_tmp/bin/"*

TEST_TMP="$test_tmp" XDG_STATE_HOME="$test_tmp/state" PATH="$test_tmp/bin:$PATH" \
  "$ROOT/bin/omarchy-audio-output-volume" raise

[[ $(<"$test_tmp/volume") == "150" ]] || fail "volume raise respects configured maximum"
[[ $(<"$test_tmp/osd") == "-i volume-high -p 150 --max 150" ]] || fail "volume OSD receives actual and maximum percentages"
pass "volume action and OSD use configured maximum"

rm "$test_tmp/state/omarchy/audio-max-volume"
printf '98\n' >"$test_tmp/volume"

TEST_TMP="$test_tmp" XDG_STATE_HOME="$test_tmp/state" PATH="$test_tmp/bin:$PATH" \
  "$ROOT/bin/omarchy-audio-output-volume" raise

[[ $(<"$test_tmp/volume") == "100" ]] || fail "volume raise defaults to 100 percent"
[[ $(<"$test_tmp/osd") == "-i volume-high -p 100 --max 100" ]] || fail "volume OSD defaults to 100 percent"
pass "volume action preserves the default maximum"
