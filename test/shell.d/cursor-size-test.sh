#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home/.config/hypr" "$tmp_dir/home/.config/gtk-3.0"

cat >"$tmp_dir/bin/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
echo ok
EOF
chmod +x "$tmp_dir/bin/hyprctl"

cat >"$tmp_dir/bin/gsettings" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$GSETTINGS_LOG"
if [[ ${1:-} == "get" ]]; then
  printf "'%s'\n" "${3:-}"
fi
EOF
chmod +x "$tmp_dir/bin/gsettings"

cat >"$tmp_dir/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod +x "$tmp_dir/bin/omarchy-notification-send"

cat >"$tmp_dir/bin/omarchy-hook" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOOK_LOG"
EOF
chmod +x "$tmp_dir/bin/omarchy-hook"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
export DBUS_SESSION_BUS_ADDRESS="test"
export HYPRCTL_LOG="$tmp_dir/hyprctl"
export GSETTINGS_LOG="$tmp_dir/gsettings"
export NOTIFY_LOG="$tmp_dir/notify"
export HOOK_LOG="$tmp_dir/hook"
unset HYPRCURSOR_SIZE XCURSOR_SIZE

[[ $(omarchy-cursor-size-list | tr '\n' ' ') == "16 20 24 28 32 36 40 44 48 56 64 " ]] ||
  fail "cursor size list emits standard sizes" "$(omarchy-cursor-size-list | tr '\n' ' ')"
pass "cursor size list emits standard sizes"

cat >"$HOME/.config/hypr/hyprland.lua" <<'EOF'
-- test config
hl.env("XCURSOR_THEME", "macOS-original")
hl.env("HYPRCURSOR_THEME", "macOS-original")
hl.env("XCURSOR_SIZE", "64")
hl.env("HYPRCURSOR_SIZE", "64")
EOF

[[ $(omarchy-cursor-size-current) == "64" ]] ||
  fail "cursor size current reads the Hyprland config"
pass "cursor size current reads the Hyprland config"

omarchy-cursor-size-set 32

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor macOS-original 32" ]] ||
  fail "cursor size applies the theme at the requested size" "$(tail -n 1 "$HYPRCTL_LOG")"
pass "cursor size applies the theme at the requested size"

rg -q 'XCURSOR_SIZE", "32"' "$HOME/.config/hypr/hyprland.lua" &&
  rg -q 'HYPRCURSOR_SIZE", "32"' "$HOME/.config/hypr/hyprland.lua" ||
  fail "cursor size persists both env variables"
pass "cursor size persists both env variables"

[[ $(<"$HOME/.config/gtk-3.0/settings.ini") == $'[Settings]\ngtk-cursor-theme-name=macOS-original\ngtk-cursor-theme-size=32' ]] ||
  fail "cursor size writes GTK settings" "$(<"$HOME/.config/gtk-3.0/settings.ini")"
pass "cursor size writes GTK settings"

tail -n 2 "$GSETTINGS_LOG" | rg -q 'cursor-size 32' ||
  fail "cursor size syncs gsettings"
pass "cursor size syncs gsettings"

tail -n 1 "$NOTIFY_LOG" | rg -q '32' ||
  fail "cursor size notifies"
pass "cursor size notifies"

tail -n 1 "$HOOK_LOG" | rg -q 'cursor-size-set 32' ||
  fail "cursor size runs the size hook"
pass "cursor size runs the size hook"

if omarchy-cursor-size-set 0; then
  fail "cursor size rejects zero"
fi
pass "cursor size rejects zero"

if omarchy-cursor-size-set abc; then
  fail "cursor size rejects non-numeric sizes"
fi
pass "cursor size rejects non-numeric sizes"

rg -F '"style.cursor-style": {"icon":"󰇀","label":"Cursor Style","aliases":["cursor","cursor-picker"]}' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null ||
  fail "menu defines the cursor style parent"
pass "menu defines the cursor style parent"

rg -F '"style.cursor-style.theme": {"icon":"󰇀","label":"Theme","aliases":["cursor-theme","mouse-cursor"],"provider":"cursors"}' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null ||
  fail "menu defines the cursor theme entry"
pass "menu defines the cursor theme entry"

rg -F '"style.cursor-style.size": {"icon":"󰹵","label":"Size","aliases":["cursor-size"],"provider":"cursor-sizes"}' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null ||
  fail "menu defines the cursor size entry"
pass "menu defines the cursor size entry"

rg -F '"cursor-sizes": {' "$ROOT/shell/plugins/menu/Menu.qml" >/dev/null &&
  rg -F 'omarchy-cursor-size-set' "$ROOT/shell/plugins/menu/Menu.qml" >/dev/null ||
  fail "menu wires the cursor size provider"
pass "menu wires the cursor size provider"

mv "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua.bak"
export HYPRCURSOR_THEME="macOS-original"
[[ $(omarchy-cursor-current) == "macOS-original" ]] ||
  fail "cursor theme current falls back to the session env"
pass "cursor theme current falls back to the session env"
unset HYPRCURSOR_THEME
mv "$HOME/.config/hypr/hyprland.lua.bak" "$HOME/.config/hypr/hyprland.lua"
