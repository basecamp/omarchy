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

for command in omarchy-theme-set-codex omarchy-theme-set-grok omarchy-theme-set-pi omarchy-theme-set-claude; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$OMARCHY_TEST_APP_THEME_CALLS"
SH
  chmod +x "$mock_bin/$command"
done

calls="$test_tmp/theme-calls"
app_theme_calls="$test_tmp/app-theme-calls"
touch "$test_tmp/home/.config/chromium/SingletonLock"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_THEME_CALLS="$calls" OMARCHY_TEST_APP_THEME_CALLS="$app_theme_calls" \
  bash "$ROOT/install/user/theme.sh"
grep -Fx 'Tokyo Night' "$calls" >/dev/null || fail "user theme setup seeds Tokyo Night when no theme exists"
[[ -f $test_tmp/home/.config/chromium/SingletonLock ]] || fail "runtime user theme setup preserves Chromium's singleton lock"
for command in codex grok pi claude; do
  grep -Fx "omarchy-theme-set-$command --activate" "$app_theme_calls" >/dev/null ||
    fail "user theme setup activates the $command terminal theme"
done

: >"$calls"
: >"$app_theme_calls"
printf 'Solitude\n' >"$test_tmp/home/.local/state/omarchy/current/theme.name"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_THEME_CALLS="$calls" OMARCHY_TEST_APP_THEME_CALLS="$app_theme_calls" \
  bash "$ROOT/install/user/theme.sh"
[[ ! -s $calls ]] || fail "user theme setup preserves an existing theme"
[[ $(wc -l <"$app_theme_calls") == 4 ]] || fail "user theme setup activates terminal apps with an existing Omarchy theme"

pass "user theme setup seeds once and activates terminal application themes"
