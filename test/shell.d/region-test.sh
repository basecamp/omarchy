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

npm_line="registry=https://registry.npmmirror.com"
go_line="GOPROXY=https://goproxy.cn,direct"
cargo_line='registry = "sparse+https://rsproxy.cn/index/"'
gem_line="- https://mirrors.tuna.tsinghua.edu.cn/rubygems/"
pip_line="index-url = https://pypi.tuna.tsinghua.edu.cn/simple"

[[ $(omarchy-region) == "World" ]] || fail "region defaults to World before any choice"
pass "region defaults to World before any choice"

mkdir -p "$test_home/.config/omarchy/extensions"
cp "$ROOT/config/omarchy/extensions/omarchy-menu.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"

omarchy-region china >/dev/null
grep -Fx "$npm_line" "$test_home/.npmrc" >/dev/null || fail "china points npm at the Chinese registry"
grep -Fx "$pip_line" "$test_home/.config/pip/pip.conf" >/dev/null || fail "china points pip at the Chinese index"
grep -Fx "$cargo_line" "$test_home/.cargo/config.toml" >/dev/null || fail "china points cargo at the Chinese registry"
grep -Fx "$go_line" "$test_home/.config/go/env" >/dev/null || fail "china points go at the Chinese proxy"
grep -Fx -- "$gem_line" "$test_home/.gemrc" >/dev/null || fail "china points gem at the Chinese source"
[[ $(omarchy-region) == "China" ]] || fail "china is stored as the region"
grep -Fx "rime-ice-installer" "$pkg_log" >/dev/null || fail "china installs the Rime Ice installer package"
(( $(wc -l <"$installer_log") == 1 )) || fail "china runs the Rime Ice installer"
grep -q "locale-gen" "$sudo_log" || fail "china generates the Chinese locale"
grep -Fx "localectl set-locale LANG=zh_CN.UTF-8" "$sudo_log" >/dev/null || fail "china sets the system language"
grep -Fx "pacman -Sy" "$sudo_log" >/dev/null || fail "china syncs the repo databases before installing"
grep -A1 '^\[Groups/0/Items/0\]$' "$test_home/.config/fcitx5/profile" | grep -qFx "Name=rime" ||
  fail "china makes Rime the first input method"
grep -qFx "DefaultIM=rime" "$test_home/.config/fcitx5/profile" || fail "china makes Rime the group default"
grep -qFx "0=Control+space" "$test_home/.config/fcitx5/config" || fail "china pins the Ctrl+Space toggle"
grep -Fx -- "--user restart omarchy-fcitx5.service" "$systemctl_log" >/dev/null ||
  fail "china restarts fcitx5 with the new profile"
cmp -s "$ROOT/default/omarchy/omarchy-menu.zh-cn.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  fail "china installs the Chinese menu labels"
pass "china applies every Chinese source and sets up the input method"

omarchy-region china >/dev/null
(( $(grep -cFx "$npm_line" "$test_home/.npmrc") == 1 )) || fail "reapplying china keeps one npm registry line"
(( $(grep -cFx "# Omarchy region begin" "$test_home/.cargo/config.toml") == 1 )) || fail "reapplying china keeps one cargo block"
(( $(wc -l <"$installer_log") == 1 )) || fail "reapplying china skips the installed input method"
(( $(grep -cFx "pacman -Sy" "$sudo_log") == 1 )) || fail "reapplying china skips the database sync too"
pass "reapplying china is idempotent and leaves the input method alone"

omarchy-region world >/dev/null
[[ ! -e $test_home/.npmrc ]] || fail "world removes the npm override"
[[ ! -e $test_home/.config/pip/pip.conf ]] || fail "world removes the pip override"
[[ ! -e $test_home/.cargo/config.toml ]] || fail "world removes the cargo override"
[[ ! -e $test_home/.config/go/env ]] || fail "world removes the go override"
[[ ! -e $test_home/.gemrc ]] || fail "world removes the gem override"
[[ $(omarchy-region) == "World" ]] || fail "world is stored as the region"
[[ -f $test_home/.local/share/fcitx5/rime/rime_ice.schema.yaml ]] || fail "world leaves the input method installed"
grep -qFx "DefaultIM=rime" "$test_home/.config/fcitx5/profile" || fail "world leaves the input method configured"
cmp -s "$ROOT/config/omarchy/extensions/omarchy-menu.jsonc" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  fail "world restores the sample menu extension"
pass "world removes every Chinese override and keeps the input method"

printf 'registry=https://corp.example/npm\n' >"$test_home/.npmrc"
printf 'GOPROXY=https://corp.example/go\n' >"$test_home/.config/go/env"
if omarchy-region china >/dev/null 2>"$test_tmp/refusal"; then
  fail "china refuses sources someone else configured"
fi
grep -q "npm:" "$test_tmp/refusal" || fail "china names the npm file it refuses to touch"
grep -q "go:" "$test_tmp/refusal" || fail "china names the go file it refuses to touch"
[[ ! -e $test_home/.config/pip/pip.conf ]] || fail "a refused china run applies nothing"
[[ $(omarchy-region) == "World" ]] || fail "a refused china run keeps the region"
pass "china refuses foreign sources before touching anything"

omarchy-region world >/dev/null
grep -Fx "registry=https://corp.example/npm" "$test_home/.npmrc" >/dev/null ||
  fail "world leaves a registry someone else configured"
grep -Fx "GOPROXY=https://corp.example/go" "$test_home/.config/go/env" >/dev/null ||
  fail "world leaves a proxy someone else configured"
pass "world only removes the values Omarchy wrote"
rm "$test_home/.npmrc" "$test_home/.config/go/env"

mkdir -p "$test_home/.cargo"
printf '[source.crates-io]\nreplace-with = "corp"\n' >"$test_home/.cargo/config.toml"
if omarchy-region china >/dev/null 2>"$test_tmp/cargo-refusal"; then
  fail "china refuses a hand-written crates-io source"
fi
grep -q "cargo:" "$test_tmp/cargo-refusal" || fail "china names the cargo file it refuses to touch"
pass "china refuses a hand-written crates-io source"
rm "$test_home/.cargo/config.toml"

printf -- '---\n:sources:\n- https://corp.example/gems\n' >"$test_home/.gemrc"
if omarchy-region china >/dev/null 2>"$test_tmp/gem-refusal"; then
  fail "china refuses a hand-written gemrc"
fi
grep -q "gem:" "$test_tmp/gem-refusal" || fail "china names the gem file it refuses to touch"
pass "china refuses a hand-written gemrc"
rm "$test_home/.gemrc"

mkdir -p "$test_home/.config/pip"
printf '# mirrors for work\ntimeout = 60\n' >"$test_home/.config/pip/pip.conf"
mkdir -p "$test_home/.config/omarchy/extensions"
printf '{"apps": {"label":"Mine"}}\n' >"$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"
if omarchy-region china >/dev/null 2>"$test_tmp/pip-refusal"; then
  fail "china refuses a hand-written pip.conf"
fi
grep -q "pip:" "$test_tmp/pip-refusal" || fail "china names the pip file it refuses to touch"
grep -q "menu:" "$test_tmp/pip-refusal" || fail "china names the menu extension it refuses to touch"
pass "china refuses a hand-written pip.conf and menu extension"
rm "$test_home/.config/pip/pip.conf" "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"

if omarchy-region china unexpected >/dev/null 2>&1; then
  fail "region rejects extra arguments"
fi
[[ $(omarchy-region) == "World" ]] || fail "extra arguments change nothing"
pass "region rejects extra arguments"

printf 'registry=https://registry.npmmirror.com\nregistry=https://corp.example/npm\n' >"$test_home/.npmrc"
if omarchy-region china >/dev/null 2>"$test_tmp/npm-hidden"; then
  fail "china refuses a foreign registry hiding behind the Omarchy one"
fi
grep -q "corp.example" "$test_tmp/npm-hidden" || fail "china names the hidden foreign registry"
pass "china refuses a foreign registry hiding behind the Omarchy one"
rm "$test_home/.npmrc"

mkdir -p "$test_home/.cargo"
{
  printf '[source.crates-io]\nreplace-with = "corp"\n'
  printf '# padding\n%.0s' {1..20000}
} >"$test_home/.cargo/config.toml"
if omarchy-region china >/dev/null 2>&1; then
  fail "china refuses an early crates-io source in a long cargo config"
fi
pass "china refuses an early crates-io source in a long cargo config"

printf '[source.omarchy-region]\nregistry = "corp"\n' >"$test_home/.cargo/config.toml"
if omarchy-region china >/dev/null 2>&1; then
  fail "china refuses a hand-written omarchy-region source"
fi
pass "china refuses a hand-written omarchy-region source"

printf '# hand-tuned settings\n[net]\ngit-fetch-with-cli = true' >"$test_home/.cargo/config.toml"
omarchy-region china >/dev/null
grep -Fx "# Omarchy region begin" "$test_home/.cargo/config.toml" >/dev/null ||
  fail "china keeps its cargo block intact after an unterminated final line"
omarchy-region world >/dev/null
[[ $(cat "$test_home/.cargo/config.toml") == $'# hand-tuned settings\n[net]\ngit-fetch-with-cli = true' ]] ||
  fail "world restores an unterminated cargo config's own content"
pass "cargo blocks survive a config with no trailing newline"
rm "$test_home/.cargo/config.toml"

printf 'registry=https://registry.npmmirror.com\n' >"$test_home/.npmrc"
chmod 600 "$test_home/.npmrc"
omarchy-region china >/dev/null
[[ $(stat -c %a "$test_home/.npmrc") == "600" ]] || fail "china keeps npmrc permissions"
omarchy-region world >/dev/null
[[ ! -e $test_home/.npmrc ]] || fail "world still removes the npm override after a permission check"
pass "switching regions preserves npmrc permissions"
