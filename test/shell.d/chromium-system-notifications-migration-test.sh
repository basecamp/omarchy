#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1788129995.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config_dir="$home/.config"
mkdir -p "$config_dir"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

printf '%s\n' \
  '--ozone-platform=wayland' \
  '--ozone-platform-hint=wayland' \
  '--password-store=gnome-libsecret' \
  '--enable-features=TouchpadOverscrollHistoryNavigation' \
  '--load-extension=/one,/two' >"$config_dir/chromium-flags.conf"
printf '%s\n' '--ozone-platform=wayland' >"$config_dir/brave-flags.conf"
printf '%s\n' '--enable-features=ExistingFeature' >"$config_dir/brave-origin-flags.conf"
printf '%s\n' '--disable-features=SystemNotifications' >"$config_dir/chrome-flags.conf"

run_migration

grep -Fxq -- '--enable-features=TouchpadOverscrollHistoryNavigation,SystemNotifications' "$config_dir/chromium-flags.conf" ||
  fail "migration adds system notifications to Chromium's existing feature list"
grep -Fxq -- '--ozone-platform=wayland' "$config_dir/chromium-flags.conf" ||
  fail "migration leaves flags before Chromium's feature list unchanged"
grep -Fxq -- '--load-extension=/one,/two' "$config_dir/chromium-flags.conf" ||
  fail "migration leaves flags after Chromium's feature list unchanged"
[[ $(grep -o 'SystemNotifications' "$config_dir/chromium-flags.conf" | wc -l) -eq 1 ]] ||
  fail "migration changes only Chromium's feature list"
grep -Fxq -- '--enable-features=SystemNotifications' "$config_dir/brave-flags.conf" ||
  fail "migration adds a feature list when Brave does not have one"
grep -Fxq -- '--enable-features=ExistingFeature,SystemNotifications' "$config_dir/brave-origin-flags.conf" ||
  fail "migration preserves custom Brave Origin features"
[[ $(<"$config_dir/chrome-flags.conf") == '--disable-features=SystemNotifications' ]] ||
  fail "migration preserves an explicit system-notification opt-out"
pass "migration enables system notifications without discarding browser flag choices"

run_migration

[[ $(grep -o 'SystemNotifications' "$config_dir/chromium-flags.conf" | wc -l) -eq 1 ]] ||
  fail "migration is idempotent for an existing feature list"
[[ $(grep -o 'SystemNotifications' "$config_dir/brave-flags.conf" | wc -l) -eq 1 ]] ||
  fail "migration is idempotent for an added feature list"
pass "migration does not duplicate the system notification feature"
