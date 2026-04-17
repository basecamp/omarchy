#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ $expected != "$actual" ]]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ $haystack != *"$needle"* ]] || fail "$message"
}

setup_env() {
  TEST_ROOT=$(mktemp -d)
  export HOME="$TEST_ROOT/home"
  export TEST_BIN="$TEST_ROOT/bin"
  export USER="tester"
  export PATH="$TEST_BIN:/usr/bin:/bin"

  mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy/extensions" "$TEST_BIN"
  : >"$TEST_ROOT/walker.responses"
  : >"$TEST_ROOT/walker.calls"

  cat >"$TEST_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF

  cat >"$TEST_BIN/omarchy-launch-walker" <<'EOF'
#!/bin/bash
set -euo pipefail

responses_file="${TEST_ROOT}/walker.responses"
calls_file="${TEST_ROOT}/walker.calls"
response=$(head -n 1 "$responses_file")
tail -n +2 "$responses_file" >"$responses_file.tmp" || true
mv "$responses_file.tmp" "$responses_file"
printf '%s\n' "$*" >>"$calls_file"
printf '%s\n' "$response"
EOF

  cat >"$TEST_BIN/omarchy-setup-defaults" <<'EOF'
#!/bin/bash
set -euo pipefail

printf 'defaults\n' >>"${TEST_ROOT}/events.log"
exit 1
EOF

  cat >"$TEST_BIN/omarchy-launch-wifi" <<'EOF'
#!/bin/bash
set -euo pipefail

printf 'wifi\n' >>"${TEST_ROOT}/events.log"
EOF

  cat >"$TEST_BIN/omarchy-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
set -euo pipefail

printf 'terminal:%s\n' "$*" >>"${TEST_ROOT}/events.log"
EOF

  cat >"$TEST_BIN/omarchy-defaults" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
summary)
  printf 'shell|/usr/bin/zsh|Zsh\n'
  ;;
list)
  printf '/bin/bash|Bash\n/usr/bin/zsh|Zsh\n'
  ;;
current)
  printf '/usr/bin/zsh\n'
  ;;
label)
  case "${3:-}" in
  /bin/bash) printf 'Bash\n' ;;
  /usr/bin/zsh) printf 'Zsh\n' ;;
  *) printf '%s\n' "${3:-}" ;;
  esac
  ;;
note)
  printf 'requires relogin\n'
  ;;
*)
  exit 0
  ;;
esac
EOF

  cat >"$TEST_BIN/notify-send" <<'EOF'
#!/bin/bash
exit 0
EOF

  chmod +x "$TEST_BIN"/*
  export TEST_ROOT
}

test_setup_defaults_returns_to_setup_menu() {
  printf '  Default Apps\n  Wifi\n' >"$TEST_ROOT/walker.responses"

  bash "$REPO_ROOT/bin/omarchy-menu" setup >/dev/null 2>&1 || true

  assert_equals $'defaults\nwifi' "$(cat "$TEST_ROOT/events.log")" "defaults should return to setup menu and allow choosing another setup entry"
  assert_equals "2" "$(wc -l <"$TEST_ROOT/walker.calls" | tr -d ' ')" "setup walker should open twice"
}

test_setup_direct_action_closes_without_reopening() {
  : >"$TEST_ROOT/events.log"
  : >"$TEST_ROOT/walker.calls"
  printf '  Wifi\n' >"$TEST_ROOT/walker.responses"

  bash "$REPO_ROOT/bin/omarchy-menu" setup >/dev/null 2>&1 || true

  assert_equals "wifi" "$(cat "$TEST_ROOT/events.log")" "setup direct actions should execute once"
  assert_equals "1" "$(wc -l <"$TEST_ROOT/walker.calls" | tr -d ' ')" "setup should close after a final direct action"
}

test_defaults_width_is_not_hardcoded_large() {
  : >"$TEST_ROOT/walker.calls"
  printf 'CNCLD\n' >"$TEST_ROOT/walker.responses"

  bash "$REPO_ROOT/bin/omarchy-setup-defaults" >/dev/null 2>&1 || true

  call=$(cat "$TEST_ROOT/walker.calls")
  assert_not_contains "$call" "--width 680" "defaults menu should not hardcode width 680"
  assert_not_contains "$call" "--width 620" "defaults role menu should not hardcode width 620"
  assert_not_contains "$call" "--width 560" "defaults menu should not hardcode width 560"
}

test_defaults_applies_selection_and_exits() {
  : >"$TEST_ROOT/walker.calls"
  : >"$TEST_ROOT/apply.log"
  printf '○  Brave\n' >"$TEST_ROOT/walker.responses"

  cat >"$TEST_BIN/omarchy-defaults" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
summary)
  printf 'browser|chromium.desktop|Chromium\n'
  ;;
list)
  printf 'chromium.desktop|Chromium\nbrave-browser.desktop|Brave\n'
  ;;
current)
  printf 'chromium.desktop\n'
  ;;
label)
  case "${3:-}" in
  chromium.desktop) printf 'Chromium\n' ;;
  brave-browser.desktop) printf 'Brave\n' ;;
  *) printf '%s\n' "${3:-}" ;;
  esac
  ;;
note)
  printf 'via XDG\n'
  ;;
apply)
  printf '%s|%s\n' "$2" "$3" >>"${TEST_ROOT}/apply.log"
  ;;
*)
  exit 0
  ;;
esac
EOF
  chmod +x "$TEST_BIN/omarchy-defaults"

  bash "$REPO_ROOT/bin/omarchy-setup-defaults" browser >/dev/null 2>&1 || true

  assert_equals "browser|brave-browser.desktop" "$(cat "$TEST_ROOT/apply.log")" "selecting a candidate should apply immediately"
  assert_equals "1" "$(wc -l <"$TEST_ROOT/walker.calls" | tr -d ' ')" "direct role picker should close after applying"
}

test_defaults_main_menu_applies_and_closes() {
  : >"$TEST_ROOT/walker.calls"
  : >"$TEST_ROOT/apply.log"
  printf '  Browser       Chromium\n○  Brave\n' >"$TEST_ROOT/walker.responses"

  cat >"$TEST_BIN/omarchy-defaults" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
summary)
  printf 'browser|chromium.desktop|Chromium\n'
  ;;
list)
  printf 'chromium.desktop|Chromium\nbrave-browser.desktop|Brave\n'
  ;;
current)
  printf 'chromium.desktop\n'
  ;;
label)
  case "${3:-}" in
  chromium.desktop) printf 'Chromium\n' ;;
  brave-browser.desktop) printf 'Brave\n' ;;
  *) printf '%s\n' "${3:-}" ;;
  esac
  ;;
note)
  exit 0
  ;;
apply)
  printf '%s|%s\n' "$2" "$3" >>"${TEST_ROOT}/apply.log"
  ;;
*)
  exit 0
  ;;
esac
EOF
  chmod +x "$TEST_BIN/omarchy-defaults"

  bash "$REPO_ROOT/bin/omarchy-setup-defaults" >/dev/null 2>&1 || true

  assert_equals "browser|brave-browser.desktop" "$(cat "$TEST_ROOT/apply.log")" "selecting from the main defaults menu should apply immediately"
  assert_equals "2" "$(wc -l <"$TEST_ROOT/walker.calls" | tr -d ' ')" "defaults should close after applying instead of reopening the main menu"
}

test_nested_install_action_closes_without_reopening() {
  : >"$TEST_ROOT/events.log"
  : >"$TEST_ROOT/walker.calls"
  printf '  Service\n󰟵  Bitwarden\n' >"$TEST_ROOT/walker.responses"

  bash "$REPO_ROOT/bin/omarchy-menu" install >/dev/null 2>&1 || true

  assert_equals "terminal:echo 'Installing Bitwarden...'; omarchy-pkg-add bitwarden bitwarden-cli && setsid gtk-launch bitwarden" "$(cat "$TEST_ROOT/events.log")" "nested final actions should run once"
  assert_equals "2" "$(wc -l <"$TEST_ROOT/walker.calls" | tr -d ' ')" "nested menus should close after a final action"
}

main() {
  setup_env
  test_setup_defaults_returns_to_setup_menu
  test_setup_direct_action_closes_without_reopening
  test_defaults_width_is_not_hardcoded_large
  test_defaults_applies_selection_and_exits
  test_defaults_main_menu_applies_and_closes
  test_nested_install_action_closes_without_reopening
  echo "menu_defaults_test.sh: ok"
}

main "$@"
