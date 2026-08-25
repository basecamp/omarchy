#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
stub_bin="$test_tmp/bin"
mkdir -p "$state" "$stub_bin"

HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
  XDG_RUNTIME_DIR="$test_tmp" \
  bash "$ROOT/bin/omarchy-theme-set" "Tokyo Night"

generated_theme="$state/theme/zed.json"
[[ -f $generated_theme ]] || fail "Zed theme is generated with the current theme"
jq -e '.themes[0].name == "Omarchy" and .themes[0].appearance == "dark"' "$generated_theme" >/dev/null ||
  fail "Zed theme is valid JSON with the Omarchy identity and appearance"
! grep -q '{{' "$generated_theme" || fail "Zed theme resolves every template placeholder"
pass "Zed theme is rendered by the shared theme pipeline"

HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
  XDG_RUNTIME_DIR="$test_tmp" \
  bash "$ROOT/bin/omarchy-theme-set" "Catppuccin Latte"
jq -e '.themes[0].appearance == "light"' "$generated_theme" >/dev/null ||
  fail "Zed theme follows a light Omarchy theme"
pass "Zed theme renders both dark and light appearances"

printf '#!/bin/bash\nexit 0\n' >"$stub_bin/zeditor"
chmod +x "$stub_bin/zeditor"

run_sync() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-theme-set-zed" "$@"
}

run_sync
settings="$home/.config/zed/settings.json"
installed_theme="$home/.config/zed/themes/omarchy.json"
cmp -s "$generated_theme" "$installed_theme" || fail "Zed receives the generated Omarchy theme"
[[ ! -e $settings ]] || fail "Zed theme sync does not take over the user's theme selection"
run_sync --select
jq -e '.theme == "Omarchy"' "$settings" >/dev/null || fail "Zed selects Omarchy when requested"
pass "Zed receives the generated theme and selects it only when requested"

cat >"$settings" <<'JSONC'
{
  // Keep this user preference.
  "autosave": "on_focus_change",
  "theme": "Existing"
}
JSONC
run_sync --select
grep -q '// Keep this user preference.' "$settings" || fail "Zed sync preserves JSONC comments"
grep -q '"autosave": "on_focus_change"' "$settings" || fail "Zed sync preserves unrelated settings"
grep -q '"theme": "Omarchy"' "$settings" || fail "Zed sync replaces a string theme"
pass "Zed sync updates a string theme without rewriting JSONC"

cat >"$settings" <<'JSONC'
{
  "theme": {
    "mode": "system",
    "light": "One Light",
    "dark": "One Dark"
  },
  "autosave": "on_focus_change"
}
JSONC
run_sync --select
grep -q '"theme": "Omarchy"' "$settings" || fail "Zed sync replaces a theme object"
! grep -q 'One Light\|One Dark' "$settings" || fail "Zed sync removes the old theme object"
grep -q '"autosave": "on_focus_change"' "$settings" || fail "Zed sync preserves settings after a theme object"
jq -e '.theme == "Omarchy" and .autosave == "on_focus_change"' "$settings" >/dev/null ||
  fail "Zed sync keeps settings valid after replacing a theme object"
pass "Zed sync updates Zed's light/dark theme object"

cat >"$settings" <<'JSONC'
{
  // Keep this comment too.
  "autosave": "on_focus_change",
}
JSONC
run_sync --select
grep -q '"theme": "Omarchy"' "$settings" || fail "Zed sync adds a missing theme setting"
grep -q '// Keep this comment too.' "$settings" || fail "Zed sync preserves JSONC while adding a theme"
pass "Zed sync adds its theme to existing JSONC settings"

hook_dir="$home/.config/omarchy/hooks/theme-set.d"
hook_file="$home/.config/omarchy/hooks/theme-set"
mkdir -p "$hook_dir"
cat >"$hook_file" <<'HOOK'
#!/bin/bash
echo before
# >>> omazed hook - do not edit >>>
omazed set "$1"
# <<< omazed hook - do not edit <<<
echo after
HOOK
touch "$hook_dir/omazed"
touch "$home/.config/zed/themes/omazed.json"
printf '{"theme":"Omazed"}\n' >"$settings"

cat >"$stub_bin/omarchy-pkg-drop" <<'STUB'
#!/bin/bash
printf 'drop %s\n' "$*" >>"$TEST_LOG"
STUB
cat >"$stub_bin/omarchy-theme-refresh" <<'STUB'
#!/bin/bash
echo refresh >>"$TEST_LOG"
STUB
cat >"$stub_bin/omarchy-theme-set-zed" <<'STUB'
#!/bin/bash
printf 'zed %s\n' "$*" >>"$TEST_LOG"
sed -i 's/Omazed/Omarchy/' "$HOME/.config/zed/settings.json"
STUB
chmod +x "$stub_bin/omarchy-pkg-drop" "$stub_bin/omarchy-theme-refresh" "$stub_bin/omarchy-theme-set-zed"

export TEST_LOG="$test_tmp/migration.log"
for _ in 1 2; do
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null
done

! grep -q 'omazed hook\|omazed set' "$hook_file" || fail "Zed migration removes the omazed hook block"
grep -q '^echo before$' "$hook_file" && grep -q '^echo after$' "$hook_file" ||
  fail "Zed migration preserves user theme hooks"
[[ ! -e $hook_dir/omazed ]] || fail "Zed migration removes the omazed hook fragment"
[[ ! -e $home/.config/zed/themes/omazed.json ]] || fail "Zed migration removes the generated omazed theme"
grep -q '^drop omazed$' "$TEST_LOG" || fail "Zed migration removes the external omazed package"
grep -q '^refresh$' "$TEST_LOG" || fail "Zed migration refreshes the current theme"
[[ $(grep -c '^zed --select$' "$TEST_LOG") == "1" ]] || fail "Zed migration replaces Omazed exactly once"
pass "Zed migration is idempotent and preserves user hooks"

other_home="$test_tmp/other-home"
mkdir -p "$other_home/.config/zed/themes"
printf '{"theme":"One Dark"}\n' >"$other_home/.config/zed/settings.json"
touch "$other_home/.config/zed/themes/omazed.json"

HOME="$other_home" PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null

grep -q '"theme":"One Dark"' "$other_home/.config/zed/settings.json" ||
  fail "Zed migration preserves a manually selected theme"
[[ $(grep -c '^zed --select$' "$TEST_LOG") == "1" ]] || fail "Zed migration only selects Omarchy for Omazed users"
pass "Zed migration preserves another selected theme"
