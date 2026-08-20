#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_URL_HANDLER_LAUNCH"
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_URL_HANDLER_NOTIFY"
SH
chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch"
notify_log="$test_tmp/notify"

run_handler() {
  rm -f "$launch_log" "$notify_log"
  PATH="$mock_bin:$PATH" \
    OMARCHY_TEST_URL_HANDLER_LAUNCH="$launch_log" OMARCHY_TEST_URL_HANDLER_NOTIFY="$notify_log" \
    bash "$ROOT/bin/omarchy-url-handler" "$@" 2>/dev/null
}

assert_launches() {
  local description="$1" uri="$2" expected="$3"

  run_handler "$uri" || fail "$description: handler exited non-zero"
  [[ -e $launch_log ]] || fail "$description: handler did not open a terminal"
  [[ $(<"$launch_log") == "$expected" ]] ||
    fail "$description: expected '$expected', got '$(<"$launch_log")'"
  pass "$description"
}

assert_rejects() {
  local description="$1" uri="$2"

  if run_handler "$uri"; then
    fail "$description: handler accepted the link"
  fi
  [[ ! -e $launch_log ]] || fail "$description: handler opened a terminal for a rejected link"
  [[ -e $notify_log ]] || fail "$description: handler did not notify about the rejection"
  pass "$description"
}

assert_launches "url handler runs plugin add for an encoded https repo" \
  'omarchy://plugin/add?url=https%3A%2F%2Fgithub.com%2Facme%2Fomarchy-weather.git' \
  'omarchy-plugin-add https://github.com/acme/omarchy-weather.git'

assert_launches "url handler passes --enable when enable=1" \
  'omarchy://plugin/add?url=https%3A%2F%2Fgithub.com%2Facme%2Fomarchy-weather.git&enable=1' \
  'omarchy-plugin-add https://github.com/acme/omarchy-weather.git --enable'

assert_launches "url handler accepts the plugin/install alias and unencoded URLs" \
  'omarchy://plugin/install?url=https://github.com/acme/omarchy-weather&enable=0' \
  'omarchy-plugin-add https://github.com/acme/omarchy-weather'

assert_launches "url handler accepts omarchy: without slashes" \
  'omarchy:plugin/add?url=https%3A%2F%2Fgithub.com%2Facme%2Fomarchy-weather.git' \
  'omarchy-plugin-add https://github.com/acme/omarchy-weather.git'

assert_rejects "url handler rejects ssh repo URLs" \
  'omarchy://plugin/add?url=ssh%3A%2F%2Fgit%40example.test%2Facme%2Fplugin.git'
assert_rejects "url handler rejects git ext:: transports" \
  'omarchy://plugin/add?url=ext%3A%3Ash%20-c%20id'
assert_rejects "url handler rejects option-looking repo URLs" \
  'omarchy://plugin/add?url=--upload-pack%3Did'
assert_rejects "url handler rejects local paths" \
  'omarchy://plugin/add?url=%2Ftmp%2Fplugin'
assert_rejects "url handler rejects repo URLs with whitespace" \
  'omarchy://plugin/add?url=https%3A%2F%2Fgithub.com%2Fa%20b'
assert_rejects "url handler rejects a missing url parameter" \
  'omarchy://plugin/add'
assert_rejects "url handler rejects unknown actions" \
  'omarchy://theme/install?url=https%3A%2F%2Fgithub.com%2Facme%2Ftheme.git'
assert_rejects "url handler rejects non-omarchy schemes" \
  'https://github.com/acme/omarchy-weather.git'
