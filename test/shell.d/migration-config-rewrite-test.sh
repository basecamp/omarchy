#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# A migration that edits a config's contents must leave the file itself alone.
# Replacing it with the temp file it staged the new contents in hands the
# config that file's identity: mktemp's 0600, and a regular file where a
# dotfile manager had put a symlink.

hyprland_migration=$(grep -rl 'Update Hyprland Lua entrypoint to load Omarchy bootstrap' "$ROOT/migrations" | head -n 1)
[[ -n $hyprland_migration ]] || fail "Hyprland bootstrap migration exists"

clock_migration=$(grep -rl 'Remove leading zero from bar clock date' "$ROOT/migrations" | head -n 1)
[[ -n $clock_migration ]] || fail "bar clock date migration exists"

run_migration() {
  local migration=$1 home=$2

  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# The comment and the package.path assignment under it are what the awk
# rewrite keys off, so this is a config it actually edits.
seed_hyprland() {
  local home=$1

  mkdir -p "$home/.config/hypr"
  cat >"$home/.config/hypr/hyprland.lua" <<'LUA'
-- Load user modules from ~/.config and Omarchy defaults from $OMARCHY_PATH.
package.path = os.getenv("HOME")
  .. "/.config/hypr/?.lua;"
  .. package.path

require("autostart")
LUA
}

seed_shell_json() {
  local home=$1

  mkdir -p "$home/.config/omarchy"
  cat >"$home/.config/omarchy/shell.json" <<'JSON'
{
  "bar": {
    "layout": {
      "center": [
        { "id": "omarchy.clock", "formatAlt": "dd MMMM 'W'ww yyyy" }
      ]
    }
  }
}
JSON
}

home="$TMPDIR/mode"
seed_hyprland "$home"
seed_shell_json "$home"
chmod 644 "$home/.config/hypr/hyprland.lua" "$home/.config/omarchy/shell.json"

run_migration "$hyprland_migration" "$home"
run_migration "$clock_migration" "$home"

grep -Fq '/default/hypr/bootstrap.lua' "$home/.config/hypr/hyprland.lua" ||
  fail "Hyprland migration rewrote the config"
[[ $(stat -c '%a' "$home/.config/hypr/hyprland.lua") == "644" ]] ||
  fail "Hyprland migration keeps the config mode" "mode is now $(stat -c '%a' "$home/.config/hypr/hyprland.lua")"
pass "Hyprland migration keeps the config mode"

[[ $(jq -r '.bar.layout.center[0].formatAlt' "$home/.config/omarchy/shell.json") == "d MMMM 'W'ww yyyy" ]] ||
  fail "clock migration rewrote the config"
[[ $(stat -c '%a' "$home/.config/omarchy/shell.json") == "644" ]] ||
  fail "clock migration keeps the config mode" "mode is now $(stat -c '%a' "$home/.config/omarchy/shell.json")"
pass "clock migration keeps the config mode"

# A dotfile manager owns the file and leaves a symlink in ~/.config.
home="$TMPDIR/symlink"
dotfiles="$home/dotfiles"
mkdir -p "$dotfiles/hypr" "$dotfiles/omarchy"
seed_hyprland "$home"
seed_shell_json "$home"
mv "$home/.config/hypr/hyprland.lua" "$dotfiles/hypr/hyprland.lua"
mv "$home/.config/omarchy/shell.json" "$dotfiles/omarchy/shell.json"
ln -s "$dotfiles/hypr/hyprland.lua" "$home/.config/hypr/hyprland.lua"
ln -s "$dotfiles/omarchy/shell.json" "$home/.config/omarchy/shell.json"

run_migration "$hyprland_migration" "$home"
run_migration "$clock_migration" "$home"

[[ -L "$home/.config/hypr/hyprland.lua" ]] ||
  fail "Hyprland migration keeps a dotfiles symlink"
grep -Fq '/default/hypr/bootstrap.lua' "$dotfiles/hypr/hyprland.lua" ||
  fail "Hyprland migration writes through the symlink"
pass "Hyprland migration writes through a dotfiles symlink"

[[ -L "$home/.config/omarchy/shell.json" ]] ||
  fail "clock migration keeps a dotfiles symlink"
[[ $(jq -r '.bar.layout.center[0].formatAlt' "$dotfiles/omarchy/shell.json") == "d MMMM 'W'ww yyyy" ]] ||
  fail "clock migration writes through the symlink"
pass "clock migration writes through a dotfiles symlink"

# The two migrations above stand in for the rest: the whole directory has to
# stay on the write-through pattern, or the next one reintroduces this.
staged=$(grep -rn 'mv "\$tmp"' "$ROOT/migrations" || true)
[[ -z $staged ]] ||
  fail "no migration replaces a config with its staging file" "$staged"
pass "no migration replaces a config with its staging file"
