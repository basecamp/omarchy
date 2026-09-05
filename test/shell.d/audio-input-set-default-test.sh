#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-audio-input-set-default"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"
call_log="$tmpdir/calls.log"
: >"$call_log"

# Pactl card dump shaped like a real bluez headset still on A2DP.
write_cards() {
  cat >"$tmpdir/cards.txt" <<'CARDS'
Card #2
	Name: bluez_card.AA_BB_CC_DD_EE_FF
	Driver: module-bluez5-device.c
	Owner Module: 28
	Properties:
		device.description = "HUAWEI FreeBuds Pro"
	Profiles:
		a2dp-sink: High Fidelity Playback (A2DP Sink, codec AAC) (sinks: 1, sources: 0, priority: 40, available: yes)
		headset-head-unit: Headset Head Unit (HSP/HFP, codec CVSD) (sinks: 1, sources: 1, priority: 30, available: yes)
		headset-head-unit-msbc: Headset Head Unit (HSP/HFP, codec mSBC) (sinks: 1, sources: 1, priority: 30, available: yes)
		off: Off (sinks: 0, sources: 0, priority: 0, available: yes)
	Active Profile: a2dp-sink
	Ports:
		speaker-output: Speaker (type: Speaker, priority: 0, latency offset: 0 usec, available)
			Part of profile(s): a2dp-sink, headset-head-unit, headset-head-unit-msbc
		speaker-input: Microphone (type: Mic, priority: 0, latency offset: 0 usec, available)
			Part of profile(s): headset-head-unit, headset-head-unit-msbc
CARDS
}

cat >"$mock_bin/timeout" <<'SH'
#!/bin/bash
# Drop the duration argument and run the rest — tests do not need real timeouts.
shift
exec "$@"
SH
chmod +x "$mock_bin/timeout"

cat >"$mock_bin/wpctl" <<'SH'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$CALL_LOG"
SH
chmod +x "$mock_bin/wpctl"

cat >"$mock_bin/pactl" <<'SH'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$CALL_LOG"
case "$1 $2" in
  "list cards")
    cat "$CARDS_FILE"
    ;;
  "list short")
    # No active capture clients in these unit tests.
    ;;
  "set-card-profile"|"set-default-source"|"move-source-output")
    ;;
  *)
    ;;
esac
SH
chmod +x "$mock_bin/pactl"

run_helper() {
  : >"$call_log"
  CALL_LOG="$call_log" CARDS_FILE="$tmpdir/cards.txt" \
    PATH="$mock_bin:$PATH" \
    "$command" "$@"
  mapfile -t calls <"$call_log"
}

write_cards

# Non-Bluetooth source: never touch card profiles.
run_helper 43 alsa_input.pci-0000_00_1f.3.analog-stereo
printf '%s\n' "${calls[@]}" | grep -q 'set-card-profile' &&
  fail "non-bluetooth input does not change a card profile" "calls: ${calls[*]}"
printf '%s\n' "${calls[@]}" | grep -Fxq 'wpctl set-default 43' ||
  fail "non-bluetooth input still sets the default via wpctl" "calls: ${calls[*]}"
printf '%s\n' "${calls[@]}" | grep -Fxq 'pactl set-default-source alsa_input.pci-0000_00_1f.3.analog-stereo' ||
  fail "non-bluetooth input still sets the default via pactl" "calls: ${calls[*]}"
pass "non-bluetooth input does not change a card profile"

# Bluez source still on A2DP: switch to a headset profile that has a source.
run_helper 99 bluez_input.AA_BB_CC_DD_EE_FF.0
printf '%s\n' "${calls[@]}" | grep -Fxq 'pactl set-card-profile bluez_card.AA_BB_CC_DD_EE_FF headset-head-unit' ||
  fail "bluetooth input on A2DP switches the card to headset-head-unit" "calls: ${calls[*]}"
printf '%s\n' "${calls[@]}" | grep -Fxq 'wpctl set-default 99' ||
  fail "bluetooth input still sets the default via wpctl" "calls: ${calls[*]}"
printf '%s\n' "${calls[@]}" | grep -Fxq 'pactl set-default-source bluez_input.AA_BB_CC_DD_EE_FF.0' ||
  fail "bluetooth input still sets the default via pactl" "calls: ${calls[*]}"
pass "bluetooth input on A2DP switches the card to headset-head-unit"

# Prefer headset-head-unit* over a generic duplex name when both have sources.
cat >"$tmpdir/cards.txt" <<'CARDS'
Card #2
	Name: bluez_card.AA_BB_CC_DD_EE_FF
	Profiles:
		a2dp-sink: High Fidelity Playback (A2DP Sink) (sinks: 1, sources: 0, available: yes)
		handsfree-head-unit: Handsfree (sinks: 1, sources: 1, available: yes)
		headset-head-unit-msbc: Headset Head Unit (HSP/HFP, codec mSBC) (sinks: 1, sources: 1, available: yes)
	Active Profile: a2dp-sink
CARDS
run_helper 99 bluez_input.AA_BB_CC_DD_EE_FF.0
printf '%s\n' "${calls[@]}" | grep -Fxq 'pactl set-card-profile bluez_card.AA_BB_CC_DD_EE_FF headset-head-unit-msbc' ||
  fail "bluetooth input prefers headset-head-unit* when several duplex profiles exist" "calls: ${calls[*]}"
pass "bluetooth input prefers headset-head-unit* when several duplex profiles exist"

# Already on a duplex profile: leave it alone.
cat >"$tmpdir/cards.txt" <<'CARDS'
Card #2
	Name: bluez_card.AA_BB_CC_DD_EE_FF
	Profiles:
		a2dp-sink: High Fidelity Playback (A2DP Sink) (sinks: 1, sources: 0, available: yes)
		headset-head-unit: Headset Head Unit (HSP/HFP) (sinks: 1, sources: 1, available: yes)
	Active Profile: headset-head-unit
CARDS
run_helper 99 bluez_input.AA_BB_CC_DD_EE_FF.0
printf '%s\n' "${calls[@]}" | grep -q 'set-card-profile' &&
  fail "bluetooth input already on HFP does not re-set the profile" "calls: ${calls[*]}"
pass "bluetooth input already on HFP does not re-set the profile"

# Output-style bluez name still resolves the same card MAC.
write_cards
run_helper 12 bluez_output.AA_BB_CC_DD_EE_FF.a2dp-sink
printf '%s\n' "${calls[@]}" | grep -Fxq 'pactl set-card-profile bluez_card.AA_BB_CC_DD_EE_FF headset-head-unit' ||
  fail "bluetooth output-shaped name still switches the card for capture" "calls: ${calls[*]}"
pass "bluetooth output-shaped name still switches the card for capture"
