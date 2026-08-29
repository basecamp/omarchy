#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
marker="$test_home/.local/state/omarchy/preinstalls-removed"
pkg_log="$test_tmp/packages"
mise_log="$test_tmp/mise"
mkdir -p "$mock_bin" "$test_home/.local/state/omarchy" "$test_home/.local/bin" "$test_home/.local/share/applications"

for command in omarchy-webapp-remove-all omarchy-tui-remove-all omarchy-refresh-applications hyprctl; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done

cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
[[ $1 == confirm ]] && exit "${OMARCHY_TEST_CONFIRM:-0}"
if [[ $1 == choose ]]; then
  if [[ -n ${OMARCHY_TEST_CHOOSE-} ]]; then
    printf '%s\n' "$OMARCHY_TEST_CHOOSE"
    exit 0
  fi
  exit 1
fi
exit 0
SH

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_PKG_LOG"
exit "${OMARCHY_TEST_PKG_ADD_STATUS:-0}"
SH

cat >"$mock_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_PKG_LOG"
SH

cat >"$mock_bin/omarchy-mise-install" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_LOG"
SH

chmod +x "$mock_bin"/*

export PATH="$mock_bin:$PATH"
export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_PKG_LOG="$pkg_log"
export OMARCHY_TEST_MISE_LOG="$mise_log"

source "$ROOT/default/omarchy/preinstalls.sh"

# Both scripts restore and remove the same set, and every package in it has to be
# one Omarchy actually ships, or Remove Preinstalls takes out an app the user
# chose from the menu and Install Preinstalls puts back one we retired.
mapfile -t shipped < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/omarchy-base.packages")

"$ROOT/bin/omarchy-install-preinstalls" --all >/dev/null
mapfile -t restored <"$pkg_log"

"$ROOT/bin/omarchy-remove-preinstalls" --all >/dev/null
mapfile -t dropped <"$pkg_log"

[[ ${restored[*]} == "${dropped[*]}" ]] ||
  fail "Install and Remove Preinstalls cover the same packages" \
    "restored: ${restored[*]}
dropped:  ${dropped[*]}"
pass "Install and Remove Preinstalls cover the same packages"

[[ ${restored[*]} == "${PREINSTALL_PACKAGES[*]}" ]] ||
  fail "the shared catalog is what --all installs and removes" \
    "catalog: ${PREINSTALL_PACKAGES[*]}
restored: ${restored[*]}"
pass "the shared catalog is what --all installs and removes"

for package in "${restored[@]}"; do
  printf '%s\n' "${shipped[@]}" | grep -qxF "$package" ||
    fail "every preinstall is shipped in omarchy-base.packages" "$package is not shipped"
done
pass "every preinstall is shipped in omarchy-base.packages"

for package in omacut omacalc omawrite; do
  printf '%s\n' "${restored[@]}" | grep -qxF "$package" ||
    fail "preinstalls cover the Omacom apps" "$package is missing"
done
pass "preinstalls cover the Omacom apps"

mapfile -t catalog_kinds < <(preinstalls_catalog | cut -f1 | sort -u)
[[ ${catalog_kinds[*]} == "agent pkg tui webapp" ]] ||
  fail "catalog covers packages, web apps, TUIs, and agents" "${catalog_kinds[*]}"
pass "catalog covers packages, web apps, TUIs, and agents"

for core in foot imv mpv; do
  preinstalls_catalog | awk -F'\t' -v name="$core" '$2 == name { found=1 } END { exit found ? 0 : 1 }' &&
    fail "core desktop $core is not a preinstall" || true
done
pass "core desktop launchers are not preinstalls"

mapfile -t mise_commands < <(awk '{ print $(NF) }' "$ROOT/install/user/mise.sh")
mapfile -t agent_commands < <(preinstalls_catalog | awk -F'\t' '$1 == "agent" { print $2 }')
[[ ${mise_commands[*]} == "${agent_commands[*]}" ]] ||
  fail "agent catalog matches install/user/mise.sh" \
    "mise: ${mise_commands[*]}
catalog: ${agent_commands[*]}"
pass "agent catalog matches install/user/mise.sh"

# The bindings key off the marker, so clearing it before the packages land would
# point them at apps that never came back.
touch "$marker"
OMARCHY_TEST_PKG_ADD_STATUS=1 "$ROOT/bin/omarchy-install-preinstalls" --all >/dev/null && status=0 || status=$?
(( status == 1 )) || fail "restore reports a failed package transaction" "exit status was $status"
[[ -f $marker ]] || fail "restore keeps the opt-out marker when packages fail to install"
pass "restore keeps the opt-out marker when packages fail to install"

"$ROOT/bin/omarchy-install-preinstalls" --all >/dev/null
[[ ! -e $marker ]] || fail "restore clears the opt-out marker once the packages are back"
pass "restore clears the opt-out marker once the packages are back"

rm -f "$marker"
"$ROOT/bin/omarchy-remove-preinstalls" >/dev/null
[[ ! -e $marker ]] || fail "cancelling Remove Preinstalls changes nothing"
pass "declining Remove Preinstalls changes nothing"

"$ROOT/bin/omarchy-remove-preinstalls" --all >/dev/null
[[ -f $marker ]] || fail "Remove Preinstalls records the opt-out"
pass "Remove Preinstalls records the opt-out"

: >"$pkg_log"
rm -f "$marker"
"$ROOT/bin/omarchy-remove-preinstalls" obsidian >/dev/null
mapfile -t dropped <"$pkg_log"
[[ ${dropped[*]} == "obsidian" ]] ||
  fail "Remove Preinstalls can drop a single package" "${dropped[*]}"
[[ ! -e $marker ]] || fail "removing one package does not opt out of the whole set"
pass "Remove Preinstalls can drop a single package"

: >"$pkg_log"
"$ROOT/bin/omarchy-install-preinstalls" obsidian >/dev/null
mapfile -t restored <"$pkg_log"
[[ ${restored[*]} == "obsidian" ]] ||
  fail "Install Preinstalls can restore a single package" "${restored[*]}"
pass "Install Preinstalls can restore a single package"

: >"$mise_log"
"$ROOT/bin/omarchy-install-preinstalls" claude >/dev/null
[[ $(<"$mise_log") == "claude" ]] ||
  fail "Install Preinstalls restores a named agent stub" "$(<"$mise_log")"
pass "Install Preinstalls restores a named agent stub"

touch "$test_home/.local/bin/claude"
"$ROOT/bin/omarchy-remove-preinstalls" claude >/dev/null
[[ ! -e $test_home/.local/bin/claude ]] || fail "Remove Preinstalls deletes a named agent stub"
pass "Remove Preinstalls deletes a named agent stub"

mkdir -p "$test_home/.local/share/applications"
cp "$ROOT/applications/WhatsApp.desktop" "$test_home/.local/share/applications/"
cat >"$test_home/.local/share/applications/Custom.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Custom
Exec=omarchy-launch-webapp https://example.com
Type=Application
DESKTOP

"$ROOT/bin/omarchy-remove-preinstalls" WhatsApp >/dev/null
[[ ! -e $test_home/.local/share/applications/WhatsApp.desktop ]] || fail "Remove Preinstalls deletes a named web app"
[[ -f $test_home/.local/share/applications/Custom.desktop ]] || fail "Remove Preinstalls leaves user web apps in place"
pass "Remove Preinstalls removes only the named shipped web app"

"$ROOT/bin/omarchy-remove-preinstalls" --all >/dev/null
[[ -f $test_home/.local/share/applications/Custom.desktop ]] ||
  fail "Remove --all leaves user-created web apps in place"
pass "Remove --all leaves user-created web apps in place"

"$ROOT/bin/omarchy-install-preinstalls" WhatsApp >/dev/null
[[ -f $test_home/.local/share/applications/WhatsApp.desktop ]] || fail "Install Preinstalls restores a named web app"
pass "Install Preinstalls restores a named web app"

if "$ROOT/bin/omarchy-remove-preinstalls" not-a-real-app >/dev/null 2>"$test_tmp/unknown.err"; then
  fail "unknown preinstall names are rejected"
fi
grep -q "Unknown preinstall: not-a-real-app" "$test_tmp/unknown.err" ||
  fail "unknown preinstall names are named in the error" "$(<"$test_tmp/unknown.err")"
pass "unknown preinstall names are rejected"
