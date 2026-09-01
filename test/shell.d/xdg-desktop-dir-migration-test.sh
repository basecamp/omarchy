#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1788129995.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mock_bin="$test_dir/bin"
home="$test_dir/home"
user_dirs="$home/.config/user-dirs.dirs"
calls="$test_dir/xdg-user-dir-calls"
mkdir -p "$mock_bin" "$home/.config"

cat >"$mock_bin/xdg-user-dirs-update" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$XDG_USER_DIR_CALLS"
printf 'XDG_DESKTOP_DIR="%s"\n' "$3" >"$HOME/.config/user-dirs.dirs"
STUB
chmod +x "$mock_bin/xdg-user-dirs-update"

run_migration() {
  HOME="$home" XDG_USER_DIR_CALLS="$calls" PATH="$mock_bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

printf 'XDG_DESKTOP_DIR="$HOME"\n' >"$user_dirs"
run_migration

desktop_dir="$home/.local/share/desktop"
[[ -d $desktop_dir ]] || fail "desktop migration creates the hidden desktop directory"
grep -qxF -- "--set DESKTOP $desktop_dir" "$calls" ||
  fail "desktop migration redirects the legacy home desktop" "$(cat "$calls")"
pass "desktop migration redirects the legacy home desktop"

run_migration
(( $(wc -l <"$calls") == 1 )) || fail "desktop migration is idempotent" "$(cat "$calls")"
pass "desktop migration is idempotent"

custom_desktop="$home/Custom Desktop"
printf 'XDG_DESKTOP_DIR="%s"\n' "$custom_desktop" >"$user_dirs"
run_migration

[[ $(cat "$user_dirs") == "XDG_DESKTOP_DIR=\"$custom_desktop\"" ]] ||
  fail "desktop migration preserves a customized desktop directory" "$(cat "$user_dirs")"
(( $(wc -l <"$calls") == 1 )) || fail "desktop migration does not call xdg-user-dirs-update for a customized desktop"
pass "desktop migration preserves a customized desktop directory"
