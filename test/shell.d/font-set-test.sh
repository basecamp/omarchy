#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
config_home="$test_tmp/xdg-config"
stub_bin="$test_tmp/bin"
mkdir -p "$home/.config" "$config_home" "$stub_bin"

cat >"$stub_bin/fc-list" <<'STUB'
#!/bin/bash
printf 'Test & | Font\n'
STUB
chmod +x "$stub_bin/fc-list"

cat >"$stub_bin/pkill" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin/pkill"

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$stub_bin/pgrep"

cat >"$stub_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
printf 'restart\n' >>"$FONT_LOG"
STUB
chmod +x "$stub_bin/omarchy-restart-shell"

cat >"$stub_bin/omarchy-hook" <<'STUB'
#!/bin/bash
printf 'hook: %s\n' "$*" >>"$FONT_LOG"
STUB
chmod +x "$stub_bin/omarchy-hook"

for terminal in alacritty kitty ghostty foot; do
  mkdir -p "$config_home/$terminal"
done
printf 'family = "Old Font"\n' >"$config_home/alacritty/alacritty.toml"
printf 'font_family Old Font\n' >"$config_home/kitty/kitty.conf"
printf 'font-family = "Old Font"\n' >"$config_home/ghostty/config"
printf 'font=Old Font:size=9\n' >"$config_home/foot/foot.ini"

mkdir -p "$home/.config/alacritty"
printf 'family = "Legacy Font"\n' >"$home/.config/alacritty/alacritty.toml"

HOME="$home" XDG_CONFIG_HOME="$config_home" FONT_LOG="$test_tmp/font.log" \
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-font-set" "Test & | Font"

grep -qxF 'family = "Test & | Font"' "$config_home/alacritty/alacritty.toml" || fail "XDG Alacritty config is updated"
grep -qxF 'font_family Test & | Font' "$config_home/kitty/kitty.conf" || fail "XDG Kitty config is updated"
grep -qxF 'font-family = "Test & | Font"' "$config_home/ghostty/config" || fail "XDG Ghostty config is updated"
grep -qxF 'font=Test & | Font:size=9' "$config_home/foot/foot.ini" || fail "XDG Foot config is updated"
grep -qxF 'family = "Legacy Font"' "$home/.config/alacritty/alacritty.toml" || fail "legacy HOME config is left untouched"
grep -q '<string>Test &amp; | Font</string>' "$config_home/fontconfig/fonts.conf" || fail "fontconfig escapes special characters"
grep -qxF 'restart' "$test_tmp/font.log" || fail "font change restarts the shell"
grep -qxF 'hook: font-set Test & | Font' "$test_tmp/font.log" || fail "font change invokes the hook"
pass "font set honors XDG_CONFIG_HOME"
