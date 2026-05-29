#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Make Shift+Enter distinguishable for terminals and Codex' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "terminal Shift+Enter migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

test_home="$TMPDIR/home"
mkdir -p \
  "$test_home/.config/alacritty" \
  "$test_home/.config/foot" \
  "$test_home/.config/ghostty" \
  "$test_home/.config/kitty"

cp "$ROOT/config/alacritty/alacritty.toml" "$test_home/.config/alacritty/alacritty.toml"
sed -i 's/\\u001B\[13;2u/\\u001B\\r/' "$test_home/.config/alacritty/alacritty.toml"

cp "$ROOT/config/kitty/kitty.conf" "$test_home/.config/kitty/kitty.conf"
sed -i '/shift+enter/d' "$test_home/.config/kitty/kitty.conf"

cp "$ROOT/config/ghostty/config" "$test_home/.config/ghostty/config"
sed -i '/shift+enter/d' "$test_home/.config/ghostty/config"

cp "$ROOT/config/foot/foot.ini" "$test_home/.config/foot/foot.ini"
sed -i '/text-bindings/,$d' "$test_home/.config/foot/foot.ini"

HOME="$test_home" bash "$migration" >/dev/null

grep -qxF '{ key = "Return", mods = "Shift", chars = "\u001B[13;2u" },' "$test_home/.config/alacritty/alacritty.toml" ||
  fail "migration updates Alacritty Shift+Return to CSI-u"
pass "migration updates Alacritty Shift+Return to CSI-u"

grep -qxF 'map shift+enter send_text all \e[13;2u' "$test_home/.config/kitty/kitty.conf" ||
  fail "migration adds Kitty Shift+Enter CSI-u binding"
grep -qxF 'map alt+shift+enter send_text all \e[13;4u' "$test_home/.config/kitty/kitty.conf" ||
  fail "migration adds Kitty Alt+Shift+Enter CSI-u binding"
pass "migration adds Kitty CSI-u bindings"

grep -qxF 'keybind = shift+enter=csi:13;2u' "$test_home/.config/ghostty/config" ||
  fail "migration adds Ghostty Shift+Enter CSI-u binding"
grep -qxF 'keybind = alt+shift+enter=csi:13;4u' "$test_home/.config/ghostty/config" ||
  fail "migration adds Ghostty Alt+Shift+Enter CSI-u binding"
pass "migration adds Ghostty CSI-u bindings"

grep -qxF '\x1b[13;2u=Shift+Return' "$test_home/.config/foot/foot.ini" ||
  fail "migration adds Foot Shift+Return CSI-u binding"
grep -qxF '\x1b[13;4u=Mod1+Shift+Return' "$test_home/.config/foot/foot.ini" ||
  fail "migration adds Foot Alt+Shift+Return CSI-u binding"
pass "migration adds Foot CSI-u bindings"

before=$(find "$test_home/.config" -type f -print0 | sort -z | xargs -0 sha256sum)
HOME="$test_home" bash "$migration" >/dev/null
after=$(find "$test_home/.config" -type f -print0 | sort -z | xargs -0 sha256sum)

[[ $before == "$after" ]] || fail "terminal Shift+Enter migration is idempotent"
pass "terminal Shift+Enter migration is idempotent"
