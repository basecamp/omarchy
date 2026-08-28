#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Stop Neovim from previewing completions inline' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "Neovim ai_cmp migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  HOME="$1" bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean for $(basename "$1")"
}

# The two lines omarchy-nvim ships in options.lua, minus the ones that would
# drag the remote clipboard provider into the test.
seed_options() {
  local home="$TMPDIR/$1"

  mkdir -p "$home/.config/nvim/lua/config"
  printf '%s\n' 'vim.opt.relativenumber = false' 'vim.g.autoformat = false' \
    >"$home/.config/nvim/lua/config/options.lua"
  printf '%s' "$home"
}

setting_count() {
  grep -c '^vim\.g\.ai_cmp = false$' "$1/.config/nvim/lua/config/options.lua"
}

# A stock options.lua gets the setting appended.
home=$(seed_options stock)
run_migration "$home"
(( $(setting_count "$home") == 1 )) || fail "migration turns ai_cmp off in a stock options.lua"
pass "migration turns ai_cmp off in a stock options.lua"

# Migrations can be rerun by hand, and every user on the machine runs this one.
run_migration "$home"
(( $(setting_count "$home") == 1 )) || fail "migration appends the setting only once"
pass "migration appends the setting only once"

# Someone who wants the inline preview keeps it: any mention of the flag is a
# deliberate answer, and the migration does not argue with it.
home=$(seed_options explicit)
printf 'vim.g.ai_cmp = true\n' >>"$home/.config/nvim/lua/config/options.lua"
run_migration "$home"
(( $(setting_count "$home") == 0 )) || fail "migration leaves a deliberate ai_cmp setting alone"
pass "migration leaves a deliberate ai_cmp setting alone"

# Neovim's config is user-owned and may not exist at all; the migration has
# nothing to repair and must not create one.
home="$TMPDIR/no-nvim"
mkdir -p "$home"
run_migration "$home"
[[ -e "$home/.config/nvim" ]] && fail "migration no-ops without a Neovim config"
pass "migration no-ops without a Neovim config"
