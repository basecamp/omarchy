#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
cards="$test_tmp/cards.json"
sinks="$test_tmp/sinks.json"
mkdir -p "$stub_bin"

cat >"$cards" <<'JSON'
[
  {
    "name": "alsa_card.gpu",
    "active_profile": "output:hdmi-stereo",
    "profiles": {
      "output:hdmi-stereo": { "description": "Digital Stereo (HDMI) Output", "sinks": 1, "priority": 5900, "available": true },
      "output:hdmi-stereo-extra1": { "description": "Digital Stereo (HDMI 2) Output", "sinks": 1, "priority": 5700, "available": true },
      "output:hdmi-surround-extra1": { "description": "Digital Surround 5.1 (HDMI 2) Output", "sinks": 1, "priority": 600, "available": true },
      "output:hdmi-stereo-extra2": { "description": "Digital Stereo (HDMI 3) Output", "sinks": 1, "priority": 5700, "available": false }
    },
    "ports": {
      "hdmi-output-0": {
        "description": "HDMI / DisplayPort",
        "priority": 5900,
        "availability": "available",
        "properties": { "device.product.name": "Left Monitor" },
        "profiles": ["output:hdmi-stereo"]
      },
      "hdmi-output-1": {
        "description": "HDMI / DisplayPort 2",
        "priority": 5800,
        "availability": "available",
        "properties": { "device.product.name": "Right Monitor" },
        "profiles": ["output:hdmi-stereo-extra1", "output:hdmi-surround-extra1"]
      },
      "hdmi-output-2": {
        "description": "HDMI / DisplayPort 3",
        "priority": 5700,
        "availability": "not available",
        "properties": {},
        "profiles": ["output:hdmi-stereo-extra2"]
      }
    }
  }
]
JSON

cat >"$sinks" <<'JSON'
[
  {
    "index": 731,
    "name": "alsa_output.gpu.hdmi-stereo-extra1",
    "properties": {
      "device.name": "alsa_card.gpu",
      "device.profile.name": "hdmi-stereo-extra1"
    }
  }
]
JSON

cat >"$stub_bin/pactl" <<'SH'
#!/bin/bash

if [[ $1 == "-f" && $2 == "json" && $3 == "list" && $4 == "cards" ]]; then
  cat "$CARDS_FIXTURE"
elif [[ $1 == "-f" && $2 == "json" && $3 == "list" && $4 == "sinks" ]]; then
  cat "$SINKS_FIXTURE"
elif [[ $1 == "set-card-profile" ]]; then
  printf 'set-card-profile\t%s\t%s\n' "$2" "$3" >>"$CALL_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-audio-output-set-default" <<'SH'
#!/bin/bash

printf 'set-default\t%s\t%s\n' "$1" "$2" >>"$CALL_LOG"
SH

chmod +x "$stub_bin/pactl" "$stub_bin/omarchy-audio-output-set-default"

profiles=$(CARDS_FIXTURE="$cards" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-audio-output-profiles")
if jq -e '
  length == 2
  and any(.[]; .cardName == "alsa_card.gpu" and .profileName == "output:hdmi-stereo" and .label == "Left Monitor")
  and any(.[]; .cardName == "alsa_card.gpu" and .profileName == "output:hdmi-stereo-extra1" and .label == "Right Monitor")
' <<<"$profiles" >/dev/null; then
  pass "audio output profiles list the best profile for each available port"
else
  fail "audio output profiles list the best profile for each available port" "$profiles"
fi

CARDS_FIXTURE="$cards" SINKS_FIXTURE="$sinks" CALL_LOG="$calls" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-audio-output-set-profile" alsa_card.gpu output:hdmi-stereo-extra1

if rg -F $'set-card-profile\talsa_card.gpu\toutput:hdmi-stereo-extra1' "$calls" >/dev/null; then
  pass "audio output profile selection activates the requested card profile"
else
  fail "audio output profile selection activates the requested card profile"
fi

if rg -F $'set-default\t731\talsa_output.gpu.hdmi-stereo-extra1' "$calls" >/dev/null; then
  pass "audio output profile selection promotes the recreated sink"
else
  fail "audio output profile selection promotes the recreated sink"
fi

if CARDS_FIXTURE="$cards" SINKS_FIXTURE="$sinks" CALL_LOG="$calls" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-audio-output-set-profile" alsa_card.gpu output:missing 2>/dev/null; then
  fail "audio output profile selection rejects unavailable profiles"
else
  pass "audio output profile selection rejects unavailable profiles"
fi
