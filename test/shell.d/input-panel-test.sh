#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/panels/input/Model.js')

const listing = [
  'models:',
  '- name: pc105',
  '  description: Generic 105-key PC',
  'layouts:',
  "- layout: 'us'",
  "  variant: ''",
  "  brief: 'en'",
  '  description: English (US)',
  "- layout: 'us'",
  "  variant: 'intl'",
  "  brief: 'en'",
  '  description: English (US, intl., with dead keys)',
  "- layout: 'dk'",
  "  variant: ''",
  "  brief: 'da'",
  '  description: Danish',
  'option_groups:',
  "- name: 'grp'",
  '  description: Switching to another layout'
].join('\n')

assertDeepEqual(
  model.layoutOptions(listing),
  [
    { value: 'us', label: 'English (US)', description: 'US' },
    { value: 'dk', label: 'Danish', description: 'DK' }
  ],
  'input picker lists each base layout once'
)

assertEqual(model.composeLabel('caps'), 'Caps Lock', 'input labels the default compose key')
assertEqual(model.composeLabel('ralt'), 'Right Alt', 'input labels Right Alt compose')
assertEqual(model.composeLabel('none'), 'Disabled', 'input labels disabled compose')
assertEqual(
  model.heroMeta({ primary: 'us', alternate: 'dk', compose: 'ralt' }),
  'US + DK · RIGHT ALT COMPOSE',
  'input hero summarizes both layouts and compose key'
)
assertEqual(model.parseStatus('{'), null, 'input rejects malformed status')
assertEqual(model.parseStatus('{"version":2}'), null, 'input rejects an unknown status version')
assertEqual(model.parseStatus('{"version":1,"primary":"us"}').primary, 'us', 'input accepts current status')
JS

tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_home/bin"
cat >"$tmp_home/bin/hyprctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$tmp_home/bin/hyprctl"

status=$(HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" status)
jq -e '
  .primary == "us" and .alternate == "" and .compose == "caps" and
  .superKey == "super" and .numlock == true and .sensitivity == 0 and
  .naturalScroll == false and .clickfinger == true and .disableWhileTyping == true
' <<<"$status" >/dev/null || fail "input config reports Omarchy defaults" "$status"
pass "input config reports Omarchy defaults"

HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" set alternate dk >/dev/null
HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" set compose ralt >/dev/null
HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" set superKey alt >/dev/null
HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" set sensitivity -0.35 >/dev/null

generated="$tmp_home/.local/state/omarchy/hypr/input.lua"
[[ -f $generated ]] || fail "input config generates a Hyprland override"
grep -F 'kb_layout = "us,dk"' "$generated" >/dev/null || fail "input config writes the alternate layout"
grep -F 'kb_options = "compose:ralt,grp:alts_toggle,altwin:swap_alt_win"' "$generated" >/dev/null || fail "input config composes keyboard options"
grep -F 'sensitivity = -0.35' "$generated" >/dev/null || fail "input config writes pointer sensitivity"
pass "input config generates a focused Hyprland override"

saved=$(HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" status)
jq -e '.alternate == "dk" and .compose == "ralt" and .superKey == "alt" and .sensitivity == -0.35' <<<"$saved" >/dev/null ||
  fail "input config persists panel state" "$saved"
pass "input config persists panel state"

if HOME="$tmp_home" PATH="$tmp_home/bin:$PATH" "$ROOT/bin/omarchy-input-config" set sensitivity 2 >/dev/null 2>&1; then
  fail "input config rejects out-of-range sensitivity"
fi
pass "input config rejects out-of-range sensitivity"

grep -F 'dofile(input_panel)' "$ROOT/default/hypr/toggles.lua" >/dev/null ||
  fail "Hyprland loads the generated input override"
pass "Hyprland loads the generated input override"
