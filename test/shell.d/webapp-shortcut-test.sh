#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
apps="$home/.local/share/applications"
generated="$home/.local/state/omarchy/webapp-shortcuts.lua"
mkdir -p "$apps"

export HOME="$home"
export XDG_STATE_HOME="$home/.local/state"
export XDG_CONFIG_HOME="$home/.config"
export OMARCHY_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"

shortcut() {
  omarchy-webapp-shortcut "$@"
}

write_webapp() {
  local name="$1" url="$2"
  cat >"$apps/$name.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=$name
Comment=$name
Exec=omarchy-launch-webapp "$url"
Terminal=false
Type=Application
Icon=${name,,}
StartupNotify=true
EOF
}

# --- wiring -----------------------------------------------------------------

grep -Fq 'require("default.hypr.webapp-shortcuts")' "$ROOT/default/hypr/omarchy.lua" ||
  fail "omarchy.lua loads the compiled web app shortcuts"
pass "omarchy.lua loads the compiled web app shortcuts"

# --- sync compiles X-Omarchy-Shortcut keys --------------------------------

write_webapp "Figma" "https://www.figma.com/files"
printf 'X-Omarchy-Shortcut=SUPER + SHIFT + F\n' >>"$apps/Figma.desktop"

shortcut sync --no-reload >/dev/null
[[ -f $generated ]] || fail "sync writes the generated bindings file"
grep -Fq 'o.bind("SUPER + SHIFT + F", "Figma", {' "$generated" ||
  fail "sync emits a bind for a web app shortcut" "$(cat "$generated")"
grep -Fq 'launch = '\''omarchy-launch-webapp "https://www.figma.com/files"'\''' "$generated" ||
  fail "sync launches the web app URL" "$(cat "$generated")"
grep -Fq 'focus = "figma"' "$generated" ||
  fail "sync derives a focus match from the registrable domain" "$(cat "$generated")"
pass "sync compiles an X-Omarchy-Shortcut key into a Hyprland bind"

# --- set writes and canonicalizes a shortcut -----------------------------

write_webapp "Linear" "https://linear.app"
shortcut set Linear super shift l >/dev/null
grep -Fxq 'X-Omarchy-Shortcut=SUPER + SHIFT + L' "$apps/Linear.desktop" ||
  fail "set canonicalizes and stores the combo on the desktop file" "$(cat "$apps/Linear.desktop")"
grep -Fq 'o.bind("SUPER + SHIFT + L", "Linear", {' "$generated" ||
  fail "set recompiles the bindings file"
pass "set stores a canonical combo and recompiles"

# --- set --match overrides the derived focus pattern --------------------

shortcut set Linear SUPER SHIFT L --match "Linear" >/dev/null
grep -Fxq 'X-Omarchy-Shortcut-Match=Linear' "$apps/Linear.desktop" ||
  fail "set --match stores the focus override"
grep -Fq 'focus = "Linear"' "$generated" ||
  fail "set --match feeds the focus override into the bind"
pass "set --match overrides the focus pattern"

# --- conflicts with a shipped binding are refused ----------------------

if shortcut set Linear SUPER K >"$tmpdir/out" 2>"$tmpdir/err"; then
  fail "set refuses a combo already bound by Omarchy" "$(cat "$tmpdir/out")"
fi
grep -Fq 'already bound' "$tmpdir/err" ||
  fail "set explains the refusal" "$(cat "$tmpdir/err")"
grep -Fxq 'X-Omarchy-Shortcut=SUPER + SHIFT + L' "$apps/Linear.desktop" ||
  fail "a refused set leaves the existing shortcut untouched"
pass "set refuses a combo already claimed by a shipped binding"

shortcut set Linear SUPER K --force >/dev/null
grep -Fxq 'X-Omarchy-Shortcut=SUPER + K' "$apps/Linear.desktop" ||
  fail "set --force takes a claimed combo"
pass "set --force overrides a conflict"

# --- conflicts also cover the user's own bindings.lua ------------------

mkdir -p "$home/.config/hypr"
cat >"$home/.config/hypr/bindings.lua" <<'LUA'
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")
o.bind("SUPER + SHIFT + J", "Journal", "obsidian")
LUA
write_webapp "Slack" "https://app.slack.com/client"

if shortcut set Slack SUPER SHIFT J >/dev/null 2>&1; then
  fail "set refuses a combo the user bound in their own bindings.lua"
fi
shortcut set Slack SUPER SHIFT R >/dev/null ||
  fail "set allows a combo that only appears commented out in bindings.lua"
pass "set reads live bindings from bindings.lua but ignores commented-out ones"

shortcut unset Slack >/dev/null
rm -f "$home/.config/hypr/bindings.lua"

# --- unset clears the keys and recompiles -----------------------------

shortcut unset Linear >/dev/null
if grep -q '^X-Omarchy-Shortcut' "$apps/Linear.desktop"; then
  fail "unset removes every shortcut key from the desktop file"
fi
if grep -Fq '"Linear"' "$generated"; then
  fail "unset drops the bind from the compiled file"
fi
pass "unset clears the shortcut and recompiles"

# --- list reports the current mappings ------------------------------

output=$(shortcut list)
grep -Fq "Figma" <<<"$output" || fail "list shows a web app with a shortcut" "$output"
grep -Fq "SUPER + SHIFT + F" <<<"$output" || fail "list shows the canonical combo" "$output"
if grep -Fq "Linear" <<<"$output"; then
  fail "list omits a web app with no shortcut" "$output"
fi
pass "list reports web apps that have a shortcut"

# --- install accepts a shortcut argument ---------------------------

rm -f "$apps"/*.desktop
omarchy-webapp-install "Notion" "https://www.notion.so" "webapp" "" "" "SUPER SHIFT ALT N" >/dev/null 2>&1
grep -Fxq 'X-Omarchy-Shortcut=SUPER + ALT + SHIFT + N' "$apps/Notion.desktop" ||
  fail "webapp install stores the shortcut argument" "$(cat "$apps/Notion.desktop")"
grep -Fq 'o.bind("SUPER + ALT + SHIFT + N", "Notion", {' "$generated" ||
  fail "webapp install compiles the shortcut" "$(cat "$generated")"
pass "webapp install assigns a shortcut passed as an argument"
