#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-audio-output-sink" <<'SH'
#!/bin/bash
echo "test-sink"
SH

cat >"$mock_bin/pactl" <<'SH'
#!/bin/bash
case "$1 $2" in
  "get-sink-volume test-sink")
    echo "Volume: front-left: 100% / front-right: 100%"
    ;;
  "get-sink-mute test-sink")
    echo "Mute: no"
    ;;
  "set-sink-mute test-sink")
    ;;
  "set-sink-volume test-sink")
    echo "$3" >"$OMARCHY_TEST_LAST_VOLUME"
    ;;
  *)
    echo "unexpected pactl call: $*" >&2
    exit 1
    ;;
esac
SH

cat >"$mock_bin/omarchy-osd" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_OSD_LOG"
SH

chmod +x "$mock_bin"/*

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_LAST_VOLUME="$test_tmp/last-volume"
export OMARCHY_TEST_OSD_LOG="$test_tmp/osd-log"

omarchy-audio-output-volume raise
[[ $(<"$OMARCHY_TEST_LAST_VOLUME") == "105%" ]] ||
  fail "volume raise steps by five below the cap"

: >"$OMARCHY_TEST_LAST_VOLUME"
printf 'Volume: front-left: 148%% / front-right: 148%%\n' >"$test_tmp/current-volume"
cat >"$mock_bin/pactl" <<SH
#!/bin/bash
case "\$1 \$2" in
  "get-sink-volume test-sink")
    cat "$test_tmp/current-volume"
    ;;
  "get-sink-mute test-sink")
    echo "Mute: no"
    ;;
  "set-sink-mute test-sink")
    ;;
  "set-sink-volume test-sink")
    echo "\$3" >"$OMARCHY_TEST_LAST_VOLUME"
    ;;
  *)
    echo "unexpected pactl call: \$*" >&2
    exit 1
    ;;
esac
SH
chmod +x "$mock_bin/pactl"

omarchy-audio-output-volume +5
[[ $(<"$OMARCHY_TEST_LAST_VOLUME") == "150%" ]] ||
  fail "volume raise caps at one hundred fifty percent"

pass "output volume keys allow over-amplification to one hundred fifty percent"
