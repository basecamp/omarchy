#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# Super + Shift + S is a default binding now, and Hyprland stacks duplicate
# binds rather than replacing them. The migration's job is therefore to make a
# user's own binding of that chord the only one that runs, without touching the
# binding itself.

migration="$ROOT/migrations/1787870942.sh"
[[ -f $migration ]] || fail "screenshot binding migration exists" "missing $migration"
pass "screenshot binding migration exists"

run_migration() {
  local home="$1"
  ( HOME="$home"; source "$migration" >/dev/null 2>&1 )
}

with_bindings() {
  local home; home=$(mktemp -d)
  mkdir -p "$home/.config/hypr"
  printf '%s' "$1" >"$home/.config/hypr/bindings.lua"
  echo "$home"
}

unbinds() { grep -c '^[[:space:]]*hl\.unbind("SUPER + SHIFT + S")' "$1/.config/hypr/bindings.lua" || true; }

# A missing file is the common case on a fresh install.
home=$(mktemp -d); mkdir -p "$home/.config/hypr"
run_migration "$home" || fail "migration tolerates a missing bindings.lua" "it errored"
pass "migration tolerates a missing bindings.lua"

# The user kept the old screenshot example uncommented: their line stays, and
# the unbind above it stops the new default firing a second picker.
home=$(with_bindings 'o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
')
run_migration "$home"
out=$(cat "$home/.config/hypr/bindings.lua")
[[ $out == *'o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")'* ]] ||
  fail "the user's own binding is left exactly as they wrote it" "$out"
pass "the user's own binding is left exactly as they wrote it"
[[ $(unbinds "$home") == 1 ]] || fail "an unbind is inserted so only their binding runs" "$out"
pass "an unbind is inserted so only their binding runs"

# The chord rebound to something else stacks just as badly, so it is handled
# the same way -- this is what makes the binding theirs rather than doubled.
home=$(with_bindings 'o.bind("SUPER + SHIFT + S", "Notes", "obsidian")
')
run_migration "$home"
out=$(cat "$home/.config/hypr/bindings.lua")
[[ $out == *'"Notes", "obsidian"'* && $(unbinds "$home") == 1 ]] ||
  fail "a chord rebound to another command is unbound first, not removed" "$out"
pass "a chord rebound to another command is unbound first, not removed"

# Someone who already followed the documented pattern gets nothing added.
home=$(with_bindings 'hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Notes", "obsidian")
')
run_migration "$home"
[[ $(unbinds "$home") == 1 ]] || fail "an existing unbind is not duplicated" "$(cat "$home/.config/hypr/bindings.lua")"
pass "an existing unbind is not duplicated"

# Running twice must not keep stacking unbinds.
run_migration "$home"
[[ $(unbinds "$home") == 1 ]] || fail "migration is idempotent" "$(cat "$home/.config/hypr/bindings.lua")"
pass "migration is idempotent"

# The shipped template line is commented out, so there is nothing to fix.
home=$(with_bindings '-- o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
')
run_migration "$home"
[[ $(unbinds "$home") == 0 ]] || fail "a commented-out example is left alone" "$(cat "$home/.config/hypr/bindings.lua")"
pass "a commented-out example is left alone"

# Other bindings are none of the migration's business.
home=$(with_bindings 'o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh box")
')
run_migration "$home"
out=$(cat "$home/.config/hypr/bindings.lua")
[[ $out == 'o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh box")'* && $(unbinds "$home") == 0 ]] ||
  fail "unrelated bindings are untouched" "$out"
pass "unrelated bindings are untouched"

# Dotfile-managed configs are symlinks into a repo. Rewriting through the link
# rather than over it is what keeps the user's config attached to its source.
home=$(mktemp -d); mkdir -p "$home/.config/hypr" "$home/dotfiles"
printf 'o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")\n' >"$home/dotfiles/bindings.lua"
ln -s "$home/dotfiles/bindings.lua" "$home/.config/hypr/bindings.lua"
run_migration "$home"
[[ -L $home/.config/hypr/bindings.lua ]] || fail "a symlinked config stays a symlink" "it was replaced by a regular file"
pass "a symlinked config stays a symlink"
[[ $(cat "$home/dotfiles/bindings.lua") == *'hl.unbind("SUPER + SHIFT + S")'* ]] ||
  fail "the edit lands in the dotfile repo the link points at" "$(cat "$home/dotfiles/bindings.lua")"
pass "the edit lands in the dotfile repo the link points at"
