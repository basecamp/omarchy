#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home/.config/chromium" "$test_tmp/home/.local/state/omarchy/current"

cat >"$mock_bin/omarchy-theme-set" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_THEME_CALLS"
SH
chmod +x "$mock_bin/omarchy-theme-set"

# Record name + args so we assert finalize always activates pi/grok follow mode.
for command in omarchy-theme-set-pi omarchy-theme-set-grok; do
  cat >"$mock_bin/$command" <<SH
#!/bin/bash
printf '%s %s\n' "$command" "\$*" >>"\$OMARCHY_TEST_ACTIVATE_CALLS"
SH
  chmod +x "$mock_bin/$command"
done

calls="$test_tmp/theme-calls"
activate_calls="$test_tmp/activate-calls"
touch "$test_tmp/home/.config/chromium/SingletonLock"
: >"$activate_calls"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" \
  OMARCHY_TEST_THEME_CALLS="$calls" OMARCHY_TEST_ACTIVATE_CALLS="$activate_calls" \
  bash "$ROOT/install/user/theme.sh"
grep -Fx 'Tokyo Night' "$calls" >/dev/null || fail "user theme setup seeds Tokyo Night when no theme exists"
[[ -f $test_tmp/home/.config/chromium/SingletonLock ]] || fail "runtime user theme setup preserves Chromium's singleton lock"
grep -Fx 'omarchy-theme-set-pi --activate' "$activate_calls" >/dev/null || \
  fail "user theme setup activates pi theme follow"
grep -Fx 'omarchy-theme-set-grok --activate' "$activate_calls" >/dev/null || \
  fail "user theme setup activates grok theme follow"

: >"$calls"
: >"$activate_calls"
printf 'Solitude\n' >"$test_tmp/home/.local/state/omarchy/current/theme.name"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" \
  OMARCHY_TEST_THEME_CALLS="$calls" OMARCHY_TEST_ACTIVATE_CALLS="$activate_calls" \
  bash "$ROOT/install/user/theme.sh"
[[ ! -s $calls ]] || fail "user theme setup preserves an existing theme"
grep -Fx 'omarchy-theme-set-pi --activate' "$activate_calls" >/dev/null || \
  fail "user theme setup re-activates pi when a theme already exists"
grep -Fx 'omarchy-theme-set-grok --activate' "$activate_calls" >/dev/null || \
  fail "user theme setup re-activates grok when a theme already exists"

pass "user theme setup only seeds the default theme once"
