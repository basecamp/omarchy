#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
printf 'download-installer\n' >>"$HERMES_TEST_LOG"
while (($# > 0)); do
  if [[ $1 == "--output" ]]; then
    cp "$HERMES_TEST_INSTALLER" "$2"
    exit
  fi
  shift
done
exit 1
SH

cat >"$mock_bin/omarchy-sudo-keepalive" <<'SH'
#!/bin/bash
printf 'sudo-keepalive\n' >>"$HERMES_TEST_LOG"
SH

cat >"$mock_bin/update-desktop-database" <<'SH'
#!/bin/bash
printf 'desktop-database:%s\n' "$*" >>"$HERMES_TEST_LOG"
SH

cat >"$mock_bin/gtk-update-icon-cache" <<'SH'
#!/bin/bash
printf 'icon-cache:%s\n' "$*" >>"$HERMES_TEST_LOG"
SH

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ ${1:-} == "clients" ]]; then
  printf '%s\n' "${HERMES_TEST_CLIENTS:-[]}"
else
  printf 'hyprctl:%s\n' "$*" >>"$HERMES_TEST_LOG"
fi
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$HERMES_TEST_LOG"
SH

cat >"$mock_bin/hermes" <<'SH'
#!/bin/bash
printf 'hermes:%s\n' "$*" >>"$HERMES_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf 'install:%s\n' "$*" >>"$HERMES_TEST_LOG"
SH

chmod +x "$mock_bin"/*

fake_installer="$test_tmp/install.sh"
cat >"$fake_installer" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$HERMES_TEST_ARGS"
desktop_dir="$HOME/.hermes/hermes-agent/apps/desktop"
mkdir -p "$desktop_dir/release/linux-unpacked" "$desktop_dir/assets"
touch "$desktop_dir/release/linux-unpacked/Hermes"
chmod +x "$desktop_dir/release/linux-unpacked/Hermes"
printf 'icon\n' >"$desktop_dir/assets/icon.png"
SH
chmod +x "$fake_installer"

export HOME="$test_home"
export HERMES_TEST_ARGS="$test_tmp/installer-args"
export HERMES_TEST_INSTALLER="$fake_installer"
export HERMES_TEST_LOG="$test_tmp/hermes.log"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$PATH"

install -Dm644 "$ROOT/themes/tokyo-night/colors.toml" "$test_home/.local/state/omarchy/current/theme/colors.toml"

install_output=$(bash "$ROOT/bin/omarchy-install-ai-hermes")

[[ $(<"$HERMES_TEST_ARGS") == "--skip-setup --non-interactive --include-desktop" ]] ||
  fail "Hermes installer provisions the backend and desktop non-interactively"
[[ $(head -n 1 "$HERMES_TEST_LOG") == "sudo-keepalive" ]] ||
  fail "Hermes installer requests sudo before downloading or building"
grep -Fq "A fresh Hermes installation normally takes 10-15 minutes." <<<"$install_output" ||
  fail "Hermes installer sets an honest first-install expectation"
grep -Fq "Installing Python, voice, and wake-word dependencies" <<<"$install_output" ||
  fail "Hermes installer distinguishes dependency installation from the desktop build"
grep -Fq "Building Hermes Desktop" <<<"$install_output" ||
  fail "Hermes installer identifies the desktop build as a separate phase"
cmp -s "$ROOT/default/applications/hermes.desktop" "$HOME/.local/share/applications/hermes.desktop" ||
  fail "Hermes installer registers the bundled desktop entry"
[[ -f $HOME/.local/share/icons/hicolor/256x256/apps/hermes.png ]] ||
  fail "Hermes installer registers the desktop icon"
grep -Fxq "desktop-database:$HOME/.local/share/applications" "$HERMES_TEST_LOG" ||
  fail "Hermes installer refreshes the desktop entry database"
grep -Fxq "icon-cache:$HOME/.local/share/icons/hicolor" "$HERMES_TEST_LOG" ||
  fail "Hermes installer refreshes the user icon cache"
[[ -f $HOME/.hermes/desktop-plugins/omarchy-themes/plugin.js ]] ||
  fail "Hermes installer registers the Omarchy Desktop theme bundle"
[[ -f $HOME/.hermes/desktop-plugins/omarchy-system-theme/plugin.js ]] ||
  fail "Hermes installer registers the live Omarchy Desktop theme"
grep -Fxq 'hermes:skin use omarchy-system' "$HERMES_TEST_LOG" ||
  fail "Hermes installer activates the live Omarchy system theme"
grep -Fxq 'launch:uwsm-app -- gtk-launch hermes' "$HERMES_TEST_LOG" ||
  fail "Hermes installer opens the desktop app after installation"
pass "Hermes installer provisions, themes, and registers the native desktop app"

existing_home="$test_tmp/existing-home"
existing_desktop_dir="$existing_home/.hermes/hermes-agent/apps/desktop"
install -Dm644 "$ROOT/themes/tokyo-night/colors.toml" "$existing_home/.local/state/omarchy/current/theme/colors.toml"
mkdir -p "$existing_desktop_dir/release/linux-unpacked" "$existing_desktop_dir/assets"
touch "$existing_desktop_dir/release/linux-unpacked/Hermes"
chmod +x "$existing_desktop_dir/release/linux-unpacked/Hermes"
printf 'existing-icon\n' >"$existing_desktop_dir/assets/icon.png"
rm -f "$HERMES_TEST_ARGS"
: >"$HERMES_TEST_LOG"

existing_output=$(HOME="$existing_home" bash "$ROOT/bin/omarchy-install-ai-hermes")

[[ ! -e $HERMES_TEST_ARGS ]] ||
  fail "Hermes installer does not rebuild an existing upstream installation"
if grep -Eq '^(sudo-keepalive|download-installer)$' "$HERMES_TEST_LOG"; then
  fail "Hermes installer integrates an existing installation without sudo or downloads"
fi
grep -Fq "Hermes Desktop is already installed. Adding Omarchy integration..." <<<"$existing_output" ||
  fail "Hermes installer explains the lightweight integration path"
cmp -s "$ROOT/default/applications/hermes.desktop" "$existing_home/.local/share/applications/hermes.desktop" ||
  fail "Hermes installer registers the launcher for an existing upstream installation"
[[ -f $existing_home/.local/share/icons/hicolor/256x256/apps/hermes.png ]] ||
  fail "Hermes installer registers the icon for an existing upstream installation"
pass "Hermes installer integrates an existing upstream installation without rebuilding"

: >"$HERMES_TEST_LOG"
bash "$ROOT/bin/omarchy-launch-hermes"
grep -Fxq "launch:uwsm-app -- $HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" "$HERMES_TEST_LOG" ||
  fail "Hermes launcher starts the packaged GUI directly"
if grep -q '^install:' "$HERMES_TEST_LOG"; then
  fail "Hermes launcher does not open an installer terminal when the GUI exists"
fi
pass "Hermes launcher starts the GUI without a terminal"

: >"$HERMES_TEST_LOG"
HERMES_TEST_CLIENTS='[{"class":"Hermes","title":"Hermes","address":"0x123"}]' \
  bash "$ROOT/bin/omarchy-launch-hermes"
grep -Fq 'hyprctl:dispatch hl.dsp.focus({ window = "address:0x123" })' "$HERMES_TEST_LOG" ||
  fail "Hermes launcher focuses an existing desktop window"
if grep -q '^launch:' "$HERMES_TEST_LOG"; then
  fail "Hermes launcher does not start a duplicate desktop window"
fi
pass "Hermes launcher focuses an existing window"

: >"$HERMES_TEST_LOG"
HERMES_TEST_CLIENTS='[{"class":"google-chrome","title":"Hermes","address":"0x456"}]' \
  bash "$ROOT/bin/omarchy-launch-hermes"
grep -Fxq "launch:uwsm-app -- $HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/Hermes" "$HERMES_TEST_LOG" ||
  fail "Hermes launcher ignores matching browser tab titles"
if grep -q '^hyprctl:dispatch' "$HERMES_TEST_LOG"; then
  fail "Hermes launcher never focuses a browser tab by title"
fi
pass "Hermes launcher matches windows by class only"

missing_home="$test_tmp/missing-home"
mkdir -p "$missing_home"
: >"$HERMES_TEST_LOG"
HOME="$missing_home" bash "$ROOT/bin/omarchy-launch-hermes"
grep -Fxq 'install:omarchy-install-ai-hermes' "$HERMES_TEST_LOG" ||
  fail "Hermes launcher offers the Omarchy installer when Hermes is missing"
pass "Hermes launcher bootstraps missing installations"

[[ ! -e $ROOT/applications/hermes.desktop ]] ||
  fail "Hermes desktop entry is not part of default applications"
grep -Fxq 'Exec=omarchy-launch-hermes' "$ROOT/default/applications/hermes.desktop" ||
  fail "Hermes desktop entry uses the terminal-free Omarchy launcher"
grep -Fxq 'Terminal=false' "$ROOT/default/applications/hermes.desktop" ||
  fail "Hermes desktop entry never requests a terminal"
pass "Hermes desktop entry is installed on demand without a terminal"

grep -Fq '"install.ai.hermes"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "Omarchy menu exposes the Hermes installer under Install > AI"
grep -Fq 'omarchy-install-ai-hermes' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "Omarchy menu routes Hermes installation through its first-class command"
grep -Fq '$HOME/.local/share/applications/hermes.desktop' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "Omarchy menu offers integration when an existing Hermes install lacks its launcher"
pass "Omarchy menu exposes the Hermes installer"
