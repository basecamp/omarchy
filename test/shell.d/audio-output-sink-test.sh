#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/pactl" <<'SH'
#!/bin/bash

case "$*" in
"get-default-sink") printf '%s\n' "${TEST_DEFAULT_SINK:-easyeffects_sink}" ;;
"list sink-inputs") printf '%s' "${TEST_SINK_INPUTS:-}" ;;
"list sinks short") printf '%s' "${TEST_SINKS:-}" ;;
esac
SH

cat >"$mock_bin/pw-link" <<'SH'
#!/bin/bash
printf '%s' "${TEST_PIPEWIRE_LINKS:-}"
SH

chmod +x "$mock_bin/pactl" "$mock_bin/pw-link"

resolve_sink() {
  PATH="$mock_bin:$PATH" bash "$ROOT/bin/omarchy-audio-output-sink" "$@"
}

[[ $(resolve_sink alsa_output.pci-0000_00_1f.3.analog-stereo) == "alsa_output.pci-0000_00_1f.3.analog-stereo" ]] ||
  fail "a physical sink remains unchanged"
pass "a physical sink remains unchanged"

sink_inputs=$'Sink Input #42\n\tSink: 7\n\t\tnode.name = "easyeffects_sink.input"\n'
sinks=$'7\talsa_output.pci-0000_00_1f.3.analog-stereo\tmodule-alsa-card.c\n'
resolved=$(TEST_SINK_INPUTS="$sink_inputs" TEST_SINKS="$sinks" resolve_sink easyeffects_sink)
[[ $resolved == "alsa_output.pci-0000_00_1f.3.analog-stereo" ]] ||
  fail "the existing pactl route still resolves" "$resolved"
pass "the existing pactl route still resolves"

pipewire_links=$'easyeffects_sink:monitor_FL\n  |-> ee_soe_filter:input_FL\nee_soe_filter:output_FL\n  |-> ee_soe_equalizer:input_FL\nee_soe_equalizer:output_FL\n  |-> ee_soe_limiter:input_FL\nee_soe_limiter:output_FL\n  |-> alsa_output.pci-0000_00_1f.3.analog-stereo:playback_FL\n'
resolved=$(TEST_PIPEWIRE_LINKS="$pipewire_links" resolve_sink easyeffects_sink)
[[ $resolved == "alsa_output.pci-0000_00_1f.3.analog-stereo" ]] ||
  fail "a native EasyEffects graph resolves to its physical sink" "$resolved"
pass "a native EasyEffects graph resolves to its physical sink"

pipewire_links=$'easyeffects_sink:monitor_FL\n  |-> ee_soe_filter:input_FL\nee_soe_filter:output_FL\n  |-> ee_soe_limiter:input_FL\n'
resolved=$(TEST_PIPEWIRE_LINKS="$pipewire_links" resolve_sink easyeffects_sink)
[[ $resolved == "easyeffects_sink" ]] || fail "an idle graph falls back to the requested sink" "$resolved"
pass "an idle graph falls back to the requested sink"
