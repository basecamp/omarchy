#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1788139189.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
omarchy_path="$test_dir/omarchy"
current_theme_dir="$home/.local/state/omarchy/current/theme"
theme_name_path="$home/.local/state/omarchy/current/theme.name"
current_colors="$current_theme_dir/colors.toml"
user_themes="$home/.config/omarchy/themes"
mkdir -p "$current_theme_dir" "$omarchy_path/themes" "$user_themes"

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"
refresh_called="$test_dir/refresh-called"
theme_set_args="$test_dir/theme-set-args"

cat >"$stub_bin/omarchy-theme-refresh" <<STUB
#!/bin/bash
touch "$refresh_called"
STUB
cat >"$stub_bin/omarchy-theme-set" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$theme_set_args"
STUB
cat >"$stub_bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin"/*

write_stale_colors() {
  cat >"$1" <<'COLORS'
accent = "#336699"
selection = "#f0f0f0"

background = "#101010"
foreground = "#f0f0f0"

color0 = "#111111"
color8 = "#222222"
COLORS
}

write_healthy_colors() {
  cat >"$1" <<'COLORS'
accent = "#336699"
selection = "#222222"

background = "#101010"
foreground = "#f0f0f0"

color0 = "#111111"
color8 = "#222222"
COLORS
}

present_theme() {
  local name="$1"
  mkdir -p "$user_themes/$name"
  printf '%s\n' "$name" >"$theme_name_path"
}

run_migration() {
  rm -f "$refresh_called" "$theme_set_args"
  HOME="$home" OMARCHY_PATH="$omarchy_path" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# An affected theme has an invisible selection: it exactly matches foreground.
present_theme extra-stale
write_stale_colors "$current_colors"
run_migration
[[ -e $refresh_called ]] || fail "migration refreshes a theme whose selection matches foreground"
[[ ! -e $theme_set_args ]] || fail "migration refreshes a present theme rather than seeding the default"
pass "migration refreshes a theme whose selection matches foreground"

# A baked-in source colors.toml with the same fingerprint also triggers refresh,
# even if the staged copy was already rewritten.
write_healthy_colors "$current_colors"
write_stale_colors "$user_themes/extra-stale/colors.toml"
run_migration
[[ -e $refresh_called ]] || fail "migration refreshes when the extra theme's source colors.toml is stale"
pass "migration refreshes when the extra theme's source colors.toml is stale"
rm -f "$user_themes/extra-stale/colors.toml"

# A healthy theme, where selection differs from foreground, is left alone.
write_healthy_colors "$current_colors"
run_migration
[[ ! -e $refresh_called ]] || fail "migration leaves a theme whose selection already differs from foreground"
pass "migration leaves a theme whose selection already differs from foreground"

# No current theme (e.g. a fresh install that has not set one yet) is a no-op.
rm -f "$current_colors" "$theme_name_path"
run_migration
[[ ! -e $refresh_called ]] || fail "migration no-ops when there is no current theme"
[[ ! -e $theme_set_args ]] || fail "migration does not seed a default when theme.name is missing"
pass "migration no-ops when there is no current theme"

# A theme.name with no corresponding dirs must not fail the migrate queue.
# Seed Tokyo Night the way 1787481315 does, then let later migrations run.
write_stale_colors "$current_colors"
printf 'gone-extra\n' >"$theme_name_path"

set +e
HOME="$home" OMARCHY_PATH="$omarchy_path" PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
removed_status=$?
set -e
[[ $removed_status -eq 0 ]] || fail "migration succeeds when the current theme was removed"
[[ -e $theme_set_args ]] || fail "migration seeds Tokyo Night when the current theme was removed"
grep -Fxq 'Tokyo Night' "$theme_set_args" || fail "migration seeds Tokyo Night when the current theme was removed" "$(cat "$theme_set_args")"
[[ ! -e $refresh_called ]] || fail "migration does not refresh a theme that no longer exists"
pass "migration seeds Tokyo Night when the current theme was removed"

# Prove the migrate runner writes the marker and continues past this file.
migrations_root="$test_dir/migrate-root"
mkdir -p "$migrations_root/migrations"
cp "$migration" "$migrations_root/migrations/1788139189.sh"
cat >"$migrations_root/migrations/1788139190.sh" <<'LATER'
echo later-ran >>"$TEST_LATER"
LATER

later="$test_dir/later"
: >"$later"
write_stale_colors "$current_colors"
printf 'gone-extra\n' >"$theme_name_path"
rm -f "$refresh_called" "$theme_set_args"

HOME="$home" OMARCHY_PATH="$migrations_root" PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LATER="$later" \
  "$ROOT/bin/omarchy-migrate" >/dev/null

[[ -f $home/.local/state/omarchy/migrations/1788139189.sh ]] ||
  fail "migrate writes a marker when the current theme was removed"
[[ -f $home/.local/state/omarchy/migrations/1788139190.sh ]] ||
  fail "migrate still runs later migrations after a removed current theme"
grep -Fxq 'later-ran' "$later" || fail "later migration body ran after a removed current theme"
grep -Fxq 'Tokyo Night' "$theme_set_args" || fail "removed-theme migrate seeds Tokyo Night"
pass "removed current theme does not fail migrate or skip later migrations"

# Missing theme.name is also a successful no-op that still lets later migrates run.
rm -rf "$home/.local/state/omarchy/migrations"
rm -f "$theme_name_path" "$theme_set_args" "$refresh_called"
write_stale_colors "$current_colors"
: >"$later"

HOME="$home" OMARCHY_PATH="$migrations_root" PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LATER="$later" \
  "$ROOT/bin/omarchy-migrate" >/dev/null

[[ -f $home/.local/state/omarchy/migrations/1788139189.sh ]] ||
  fail "migrate writes a marker when theme.name is missing"
[[ -f $home/.local/state/omarchy/migrations/1788139190.sh ]] ||
  fail "migrate still runs later migrations when theme.name is missing"
grep -Fxq 'later-ran' "$later" || fail "later migration body ran when theme.name is missing"
[[ ! -e $refresh_called ]] || fail "missing theme.name does not refresh"
[[ ! -e $theme_set_args ]] || fail "missing theme.name does not seed a default"
pass "missing theme.name does not fail migrate or skip later migrations"
