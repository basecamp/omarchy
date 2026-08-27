#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
omarchy_path="$tmpdir/omarchy"

mkdir -p "$home/.config/hypr" "$omarchy_path/config/hypr"

cat >"$omarchy_path/config/hypr/bindings.lua" <<'EOF'
-- refreshed from OMARCHY_PATH
EOF

cat >"$home/.config/hypr/bindings.lua" <<'EOF'
-- existing user config
EOF

HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/bindings.lua >/dev/null

cmp -s "$omarchy_path/config/hypr/bindings.lua" "$home/.config/hypr/bindings.lua" ||
  fail "refresh-config copies from OMARCHY_PATH/config"

backup=$(find "$home/.config/hypr" -name 'bindings.lua.bak.*' -print -quit)
[[ -n $backup ]] || fail "refresh-config backs up replaced user config"
grep -Fq -- '-- existing user config' "$backup" ||
  fail "refresh-config backup contains previous user config"

pass "refresh-config copies from OMARCHY_PATH/config and backs up existing files"

if HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/missing.lua >"$tmpdir/out" 2>"$tmpdir/err"; then
  fail "refresh-config rejects configs missing from OMARCHY_PATH/config"
fi

grep -Fq 'Not a shipped user config: hypr/missing.lua' "$tmpdir/err" ||
  fail "refresh-config reports missing shipped config"

pass "refresh-config validates against OMARCHY_PATH/config"

mkdir -p "$omarchy_path/config/hypr" "$omarchy_path/config/etc" "$omarchy_path/.ssh" "$home/.ssh"
printf 'shipped\n' >"$omarchy_path/config/hypr/hyprland.lua"
printf 'prefixed-hosts\n' >"$omarchy_path/config/etc/hosts"
printf 'escaped-ssh\n' >"$omarchy_path/.ssh/authorized_keys"
printf 'secret\n' >"$home/.ssh/authorized_keys"
printf 'outside\n' >"$omarchy_path/README"

# /etc/hosts is joined as $OMARCHY_PATH/config/etc/hosts; plant that so the
# existence check would pass without the new absolute-path guard. Traversal
# dests are $home/README and $home/.ssh/authorized_keys.
for bad in \
  "../README" \
  "hypr/../../README" \
  "hypr/../../.ssh/authorized_keys" \
  "/etc/hosts"
do
  if HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" "$bad" >"$tmpdir/out" 2>"$tmpdir/err"; then
    fail "refresh-config refuses '$bad'"
  fi
  grep -Fq "Not a shipped user config: $bad" "$tmpdir/err" ||
    fail "refresh-config names the refusal for '$bad'" "$(cat "$tmpdir/err")"
done

[[ $(<$home/.ssh/authorized_keys) == "secret" ]] ||
  fail "refresh-config does not write ~/.ssh/authorized_keys through .."
[[ ! -e $home/README ]] ||
  fail "refresh-config does not write $HOME/README through .."
[[ ! -e $home/.config/etc/hosts ]] ||
  fail "refresh-config does not copy a prefixed /etc/hosts into ~/.config"

pass "refresh-config refuses .. and absolute paths"
