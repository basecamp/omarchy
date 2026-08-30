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
  // "theme": "Omazed",
  "theme": {
    "mode": "system",
    "light": "One Light",
    "dark": "One Dark"
  },
  "autosave": "on_focus_change"
}
JSONC
run_sync --select
grep -q '// "theme": "Omazed",' "$settings" || fail "Zed sync ignores a commented-out string theme"
grep -q '"theme": "Omarchy"' "$settings" || fail "Zed sync replaces a theme object"
! grep -q 'One Light\|One Dark' "$settings" || fail "Zed sync removes the old theme object"
grep -q '"autosave": "on_focus_change"' "$settings" || fail "Zed sync preserves settings after a theme object"
sed '/^[[:space:]]*\/\//d' "$settings" | jq -e '.theme == "Omarchy" and .autosave == "on_focus_change"' >/dev/null ||
  fail "Zed sync keeps settings valid after replacing a theme object"
pass "Zed sync ignores comments while updating Zed's light/dark theme object"

cat >"$settings" <<'JSONC'
{
  "theme": {
    "mode": "system",
    // A closing brace } in a comment must not terminate the object.
    "light": "One Light",
    "dark": "One Dark"
  },
  "autosave": "on_focus_change"
}
JSONC
run_sync --select
jq -e '.theme == "Omarchy" and .autosave == "on_focus_change"' "$settings" >/dev/null ||
  fail "Zed sync safely replaces a theme object containing braces in comments"
pass "Zed sync does not corrupt JSONC containing braces in comments"

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

settings_target="$home/.config/zed/settings-target.json"
mv "$settings" "$settings_target"
ln -s "$(basename "$settings_target")" "$settings"
run_sync --select
[[ -L $settings ]] || fail "Zed sync preserves a symlinked settings file"
grep -q '"theme": "Omarchy"' "$settings_target" || fail "Zed sync updates a symlink target"
rm "$settings"
mv "$settings_target" "$settings"
pass "Zed sync preserves symlinked settings"

hook_dir="$home/.config/omarchy/hooks/theme-set.d"
hook_file="$home/.config/omarchy/hooks/theme-set"
hook_target="$home/.config/omarchy/hooks/theme-set-target"
mkdir -p "$hook_dir"
cat >"$hook_target" <<'HOOK'
#!/bin/bash
echo before
# >>> omazed hook - do not edit >>>
omazed set "$1"
# <<< omazed hook - do not edit <<<
echo after
HOOK
ln -s "$(basename "$hook_target")" "$hook_file"
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
chmod +x "$stub_bin/omarchy-pkg-drop" "$stub_bin/omarchy-theme-refresh"

export TEST_LOG="$test_tmp/migration.log"
for _ in 1 2; do
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null
done

! grep -q 'omazed hook\|omazed set' "$hook_file" || fail "Zed migration removes the omazed hook block"
grep -q '^echo before$' "$hook_file" && grep -q '^echo after$' "$hook_file" ||
  fail "Zed migration preserves user theme hooks"
[[ -L $hook_file ]] || fail "Zed migration preserves a symlinked hook file"
[[ ! -e $hook_dir/omazed ]] || fail "Zed migration removes the omazed hook fragment"
[[ ! -e $home/.config/zed/themes/omazed.json ]] || fail "Zed migration removes the generated omazed theme"
grep -q '^drop omazed$' "$TEST_LOG" || fail "Zed migration removes the external omazed package"
grep -q '^refresh$' "$TEST_LOG" || fail "Zed migration refreshes the current theme"
grep -q '"theme":"Omarchy"' "$settings" || fail "Zed migration replaces the selected Omazed theme"
pass "Zed migration is idempotent and preserves user hooks"

other_home="$test_tmp/other-home"
mkdir -p "$other_home/.config/zed/themes" "$other_home/.local/state/omarchy/current/theme"
cp "$generated_theme" "$other_home/.local/state/omarchy/current/theme/zed.json"
printf '%s\n' '{' '  // "theme": "Omazed",' '  "theme": "One Dark"' '}' >"$other_home/.config/zed/settings.json"
touch "$other_home/.config/zed/themes/omazed.json"

HOME="$other_home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null

grep -q '"theme": "One Dark"' "$other_home/.config/zed/settings.json" ||
  fail "Zed migration preserves a manually selected theme"
grep -q '// "theme": "Omazed",' "$other_home/.config/zed/settings.json" ||
  fail "Zed migration ignores an Omazed reference inside a comment"
pass "Zed migration preserves another selected theme"

incomplete_home="$test_tmp/incomplete-home"
mkdir -p "$incomplete_home/.config/omarchy/hooks"
printf '%s\n' 'echo before' '# >>> omazed hook - do not edit >>>' 'echo keep me' >"$incomplete_home/.config/omarchy/hooks/theme-set"
HOME="$incomplete_home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null
grep -q '^echo keep me$' "$incomplete_home/.config/omarchy/hooks/theme-set" ||
  fail "Zed migration leaves an incomplete hook marker block untouched"
pass "Zed migration requires a complete hook marker block"

missing_theme_home="$test_tmp/missing-theme-home"
mkdir -p "$missing_theme_home/.config/zed/themes"
printf '{"theme":"Omazed"}\n' >"$missing_theme_home/.config/zed/settings.json"
touch "$missing_theme_home/.config/zed/themes/omazed.json"
if HOME="$missing_theme_home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1787583487.sh" >/dev/null 2>&1; then
  fail "Zed migration fails while a selected Omazed theme has no native replacement"
fi
[[ -e $missing_theme_home/.config/zed/themes/omazed.json ]] ||
  fail "Zed migration keeps Omazed in place until the native theme is ready"
grep -q '"theme":"Omazed"' "$missing_theme_home/.config/zed/settings.json" ||
  fail "Zed migration keeps the working selection when the native theme is unavailable"
pass "Zed migration does not remove Omazed before its replacement is ready"
