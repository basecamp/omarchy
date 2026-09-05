#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command gio

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
home="$test_tmp/home"
applications="$home/.local/share/applications"
state_file="$home/.config/chromium/Local State"
mkdir -p "$mock_bin" "$(dirname "$state_file")" "$applications"

cat >"$state_file" <<'JSON'
{
  "profile": {
    "info_cache": {
      "Default": { "name": "Personal" },
      "Profile 2": { "name": "Work" }
    }
  }
}
JSON

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
printf '%s\n' chromium.desktop
SH

cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
case $1 in
input)
  case $3 in
  "Name> ") printf '%s\n' "Profile App" ;;
  "URL> ") printf '%s\n' "https://example.com" ;;
  "Icon URL/name> ") printf '%s\n' "someicon" ;;
  esac
  ;;
choose)
  printf '%s\n' "$*" >"$GUM_CHOOSE_ARGS"
  printf '%s\n' "$GUM_PROFILE_SELECTION"
  ;;
esac
SH

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_ARGV"
SH

chmod +x "$mock_bin"/*

export HOME="$home"
export PATH="$mock_bin:$PATH"
export GUM_CHOOSE_ARGS="$test_tmp/gum-choose-args"
export OMARCHY_TEST_ARGV="$test_tmp/argv"

install_webapp() {
  GUM_PROFILE_SELECTION="$1" "$ROOT/bin/omarchy-webapp-install" >/dev/null
}

launched_arguments() {
  local file="$1" attempt

  : >"$OMARCHY_TEST_ARGV"
  gio launch "$file" >/dev/null 2>&1 || return 1
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -s $OMARCHY_TEST_ARGV ]] && break
    sleep 0.01
  done

  cat "$OMARCHY_TEST_ARGV"
}

install_webapp "Work (Profile 2)"
profiled_file="$applications/Profile App.desktop"

grep -Fq 'Automatic' "$GUM_CHOOSE_ARGS" ||
  fail "webapp profile picker offers automatic selection" "$(cat "$GUM_CHOOSE_ARGS")"
grep -Fq 'Personal (Default)' "$GUM_CHOOSE_ARGS" ||
  fail "webapp profile picker shows the default profile" "$(cat "$GUM_CHOOSE_ARGS")"
grep -Fq 'Work (Profile 2)' "$GUM_CHOOSE_ARGS" ||
  fail "webapp profile picker shows named profiles" "$(cat "$GUM_CHOOSE_ARGS")"
pass "webapp profile picker lists Chromium profiles"

mapfile -t argv < <(launched_arguments "$profiled_file")
(( ${#argv[@]} == 2 )) ||
  fail "profiled webapp launches with two arguments" "${argv[*]}"
[[ ${argv[0]} == "https://example.com" ]] ||
  fail "profiled webapp keeps its URL" "${argv[*]}"
[[ ${argv[1]} == "--profile-directory=Profile 2" ]] ||
  fail "profiled webapp passes the selected profile directory" "${argv[*]}"
pass "webapp profile picker binds the launcher to the selected profile"

install_webapp "Automatic"
automatic_argv=$(launched_arguments "$profiled_file")
[[ $automatic_argv == "https://example.com" ]] ||
  fail "automatic profile choice adds no browser profile flag" "$automatic_argv"
pass "webapp profile picker preserves automatic browser selection"

cat >"$state_file" <<'JSON'
{"profile":{"info_cache":{"Default":{"name":"Personal"}}}}
JSON
rm -f "$GUM_CHOOSE_ARGS"
install_webapp "unused"
[[ ! -e $GUM_CHOOSE_ARGS ]] ||
  fail "single-profile webapp install does not show a redundant picker" "$(cat "$GUM_CHOOSE_ARGS")"
pass "webapp profile picker stays hidden with one browser profile"
