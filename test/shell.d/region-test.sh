#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
pkg_log="$test_tmp/pkg-add"
installer_log="$test_tmp/installer"
sudo_log="$test_tmp/sudo"
systemctl_log="$test_tmp/systemctl"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_PKG_LOG"
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_SUDO_LOG"
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_SYSTEMCTL_LOG"
SH

cat >"$mock_bin/rime-ice-installer" <<'SH'
#!/bin/bash
printf 'ran\n' >>"$OMARCHY_TEST_INSTALLER_LOG"
mkdir -p "$HOME/.local/share/fcitx5/rime"
touch "$HOME/.local/share/fcitx5/rime/rime_ice.schema.yaml"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_PKG_LOG="$pkg_log"
export OMARCHY_TEST_INSTALLER_LOG="$installer_log"
export OMARCHY_TEST_SUDO_LOG="$sudo_log"
export OMARCHY_TEST_SYSTEMCTL_LOG="$systemctl_log"
export OMARCHY_PATH="$ROOT"

[[ $(omarchy-region) == "World" ]] || fail "region defaults to World before any choice"
pass "region defaults to World before any choice"

mkdir -p "$test_home/.config/omarchy/extensions"
cp "$ROOT/config/omarchy/extensions/omarchy-menu.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"

omarchy-region china >/dev/null
cmp -s "$ROOT/default/omarchy/omarchy-menu.zh-cn.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  fail "china installs the Chinese menu labels over the stock sample"
grep -q "locale-gen" "$sudo_log" || fail "china generates the Chinese locale"
grep -Fx "localectl set-locale LANG=zh_CN.UTF-8" "$sudo_log" >/dev/null || fail "china sets the system language"
grep -Fx "pacman -Sy" "$sudo_log" >/dev/null || fail "china syncs the repo databases before installing"
grep -Fx "rime-ice-installer" "$pkg_log" >/dev/null || fail "china installs the Rime Ice installer package"
(( $(wc -l <"$installer_log") == 1 )) || fail "china runs the Rime Ice installer"
grep -A1 '^\[Groups/0/Items/0\]$' "$test_home/.config/fcitx5/profile" | grep -qFx "Name=rime" ||
  fail "china makes Rime the first input method"
grep -qFx "DefaultIM=rime" "$test_home/.config/fcitx5/profile" || fail "china makes Rime the group default"
grep -qFx "0=Control+space" "$test_home/.config/fcitx5/config" || fail "china pins the Ctrl+Space toggle"
grep -Fx -- "--user restart omarchy-fcitx5.service" "$systemctl_log" >/dev/null ||
  fail "china restarts fcitx5 with the new profile"
[[ $(omarchy-region) == "China" ]] || fail "china is stored as the region"
pass "china sets up the language, menu and input method"

omarchy-region china >/dev/null
(( $(wc -l <"$installer_log") == 1 )) || fail "reapplying china skips the installed input method"
(( $(grep -cFx "pacman -Sy" "$sudo_log") == 1 )) || fail "reapplying china skips the database sync too"
pass "reapplying china is idempotent and leaves the input method alone"

omarchy-region world >/dev/null
cmp -s "$ROOT/config/omarchy/extensions/omarchy-menu.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  fail "world restores the sample menu extension"
[[ $(omarchy-region) == "World" ]] || fail "world is stored as the region"
[[ -f $test_home/.local/share/fcitx5/rime/rime_ice.schema.yaml ]] || fail "world leaves the input method installed"
grep -qFx "DefaultIM=rime" "$test_home/.config/fcitx5/profile" || fail "world leaves the input method configured"
pass "world restores the menu and keeps the input method"

printf '{"apps": {"label":"Mine"}}\n' >"$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"
if omarchy-region china >/dev/null 2>"$test_tmp/refusal"; then
  fail "china refuses a menu extension someone wrote by hand"
fi
grep -q "menu:" "$test_tmp/refusal" || fail "china names the menu extension it refuses to touch"
[[ $(omarchy-region) == "World" ]] || fail "a refused china run keeps the region"
pass "china refuses a hand-written menu extension"
grep -Fx '{"apps": {"label":"Mine"}}' "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" >/dev/null ||
  fail "a refused china run leaves the extension untouched"

omarchy-region world >/dev/null
grep -Fx '{"apps": {"label":"Mine"}}' "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" >/dev/null ||
  fail "world leaves a menu extension someone wrote by hand"
pass "world only restores the extension Omarchy wrote"

if omarchy-region china unexpected >/dev/null 2>&1; then
  fail "region rejects extra arguments"
fi
[[ $(omarchy-region) == "World" ]] || fail "extra arguments change nothing"
pass "region rejects extra arguments"
