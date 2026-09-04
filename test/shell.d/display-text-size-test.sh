#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
config_home="$test_tmp/xdg-config"
stub_bin="$test_tmp/bin"
mkdir -p "$home/.config" "$config_home" "$stub_bin"

cat >"$stub_bin/gsettings" <<'STUB'
#!/bin/bash
case "${1:-} ${2:-} ${3:-}" in
  "get org.gnome.desktop.interface font-name")
    printf "'Cantarell 11'\n"
    ;;
  "set org.gnome.desktop.interface text-scaling-factor")
    printf '%s\n' "$*" >>"$GSETTINGS_LOG"
    ;;
  *)
    printf '%s\n' "$*" >>"$GSETTINGS_LOG"
    ;;
esac
STUB
chmod +x "$stub_bin/gsettings"

cat >"$stub_bin/pkill" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin/pkill"

for terminal in alacritty kitty ghostty foot; do
  mkdir -p "$config_home/$terminal"
done
printf 'size = 9\n' >"$config_home/alacritty/alacritty.toml"
printf 'font_size 9.0\n' >"$config_home/kitty/kitty.conf"
printf 'font-size = 9\n' >"$config_home/ghostty/config"
printf 'font=monospace:size=9\n' >"$config_home/foot/foot.ini"

mkdir -p "$home/.config/alacritty"
printf 'size = 3\n' >"$home/.config/alacritty/alacritty.toml"

HOME="$home" XDG_CONFIG_HOME="$config_home" GSETTINGS_LOG="$test_tmp/gsettings.log" \
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-display-text-size" 16

grep -qxF 'size = 12' "$config_home/alacritty/alacritty.toml" || fail "XDG Alacritty config is updated"
grep -qxF 'font_size 12.0' "$config_home/kitty/kitty.conf" || fail "XDG Kitty config is updated"
grep -qxF 'font-size = 12' "$config_home/ghostty/config" || fail "XDG Ghostty config is updated"
grep -qxF 'font=monospace:size=12' "$config_home/foot/foot.ini" || fail "XDG Foot config is updated"
grep -qxF 'size = 3' "$home/.config/alacritty/alacritty.toml" || fail "legacy HOME config is left untouched"
grep -q 'set org.gnome.desktop.interface text-scaling-factor 1.3636' "$test_tmp/gsettings.log" ||
  fail "GTK scaling uses the requested size"
pass "display text size honors XDG_CONFIG_HOME"

HOME="$home" XDG_CONFIG_HOME="$config_home" GSETTINGS_LOG="$test_tmp/gsettings.log" \
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-display-text-size" reset

! grep -q '^base-size[[:space:]]*=' "$config_home/omarchy/shell.toml" ||
  fail "reset removes the shell size override"
grep -qxF 'size = 9' "$config_home/alacritty/alacritty.toml" || fail "reset restores XDG Alacritty config"
grep -qxF 'font_size 9.0' "$config_home/kitty/kitty.conf" || fail "reset restores XDG Kitty config"
grep -qxF 'font-size = 9' "$config_home/ghostty/config" || fail "reset restores XDG Ghostty config"
grep -qxF 'font=monospace:size=9' "$config_home/foot/foot.ini" || fail "reset restores XDG Foot config"
pass "display text size reset honors XDG_CONFIG_HOME"
