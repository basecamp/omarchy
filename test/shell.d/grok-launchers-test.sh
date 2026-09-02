#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grok_desktop="$ROOT/applications/Grok.desktop"
grok_build_desktop="$ROOT/applications/Grok Build.desktop"

[[ -f $grok_desktop ]] || fail "Grok chat ships as a default Apps launcher"
grep -Fxq 'Name=Grok' "$grok_desktop" || fail "Grok chat launcher is labeled Grok"
grep -Fxq 'Exec=omarchy-launch-webapp https://grok.com' "$grok_desktop" ||
  fail "Grok chat launcher opens grok.com"
grep -Fxq 'Icon=grok' "$grok_desktop" || fail "Grok chat launcher uses the grok icon"
pass "Grok chat is a default Apps launcher"

[[ -f "$grok_build_desktop" ]] || fail "Grok Build ships as a default Apps launcher"
grep -Fxq 'Name=Grok Build' "$grok_build_desktop" || fail "Grok Build launcher is labeled Grok Build"
grep -Fq 'omarchy-launch-tui --app-id=org.omarchy.agent grok --permission-mode bypassPermissions' "$grok_build_desktop" ||
  fail "Grok Build launcher starts the grok coding agent"
grep -Fxq 'Icon=grok' "$grok_build_desktop" || fail "Grok Build launcher uses the grok icon"
pass "Grok Build is a default Apps launcher"

grep -Fq 'name="Grok Build"' "$ROOT/bin/omarchy-default-agent" ||
  fail "default agent names grok as Grok Build"
pass "default agent names grok as Grok Build"

[[ -f $ROOT/applications/icons/Grok.png ]] || fail "Grok launchers ship an app icon"
pass "Grok launchers ship an app icon"

migration="$ROOT/migrations/1788238073.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
apps="$home/.local/share/applications"
mkdir -p "$apps"

run_migration() {
  HOME="$home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$migration" >/dev/null
}

run_migration || fail "migration installs the Grok launchers"
diff -q "$grok_desktop" "$apps/Grok.desktop" >/dev/null || fail "migration copies the Grok chat launcher"
diff -q "$grok_build_desktop" "$apps/Grok Build.desktop" >/dev/null || fail "migration copies the Grok Build launcher"
pass "migration installs the Grok launchers"

printf 'CUSTOM\n' >"$apps/Grok.desktop"
printf 'CUSTOM\n' >"$apps/Grok Build.desktop"
run_migration || fail "migration is idempotent"
diff -q "$grok_desktop" "$apps/Grok.desktop" >/dev/null || fail "migration refreshes a stale Grok chat launcher"
diff -q "$grok_build_desktop" "$apps/Grok Build.desktop" >/dev/null || fail "migration refreshes a stale Grok Build launcher"
pass "migration refreshes stale Grok launchers"
