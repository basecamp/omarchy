#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1781587663.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
nvim_config_dir="$home/.config/nvim"
nvim_options="$nvim_config_dir/lua/config/options.lua"
nvim_provider="$nvim_config_dir/lua/config/remote_clipboard.lua"
tmux_config="$home/.config/tmux/tmux.conf"

provider_source="$test_dir/share/remote_clipboard.lua"
mkdir -p "$(dirname "$provider_source")"
printf '%s\n' 'return { setup = function() end }' >"$provider_source"

run_migration() {
  HOME="$home" OMARCHY_NVIM_REMOTE_CLIPBOARD="${1:-$provider_source}" \
    bash -euo pipefail "$migration" >/dev/null
}

reset_home() {
  rm -rf "$home"
  mkdir -p "$home/.config/tmux"
  printf '%s\n' 'set -g mouse on' >"$tmux_config"
}

# ------------------------------------------------------------ provider present

reset_home
mkdir -p "$(dirname "$nvim_options")"
printf '%s\n' 'vim.opt.number = true' >"$nvim_options"

run_migration

[[ -f $nvim_provider ]] || fail "an installed provider lands in the user's Neovim config"
[[ $(stat -c %a "$nvim_provider") == "644" ]] ||
  fail "the installed provider keeps the shipped mode" "$(stat -c %a "$nvim_provider")"
head -n 1 "$nvim_options" | grep -qF 'require("config.remote_clipboard").setup()' ||
  fail "the provider is required from options.lua" "$(cat "$nvim_options")"
pass "an installed provider lands in the user's Neovim config"

before=$(sha256sum "$nvim_options")
run_migration
[[ $before == $(sha256sum "$nvim_options") ]] || fail "requiring the provider is idempotent" "$(cat "$nvim_options")"
pass "requiring the provider is idempotent"

# ------------------------------------------------------------ provider missing

# omarchy-nvim is its own package. Someone running their own Neovim config can
# drop it and keep ~/.config/nvim, and that must not fail the migration: a
# non-zero exit here ends the migration queue and the rest of omarchy update.
reset_home
mkdir -p "$(dirname "$nvim_options")"
printf '%s\n' 'vim.opt.number = true' >"$nvim_options"

run_migration "$test_dir/share/absent.lua" ||
  fail "a missing provider leaves the migration succeeding"
pass "a missing provider leaves the migration succeeding"

[[ ! -e $nvim_provider ]] || fail "a missing provider writes no half-installed file"
grep -qF 'config.remote_clipboard' "$nvim_options" &&
  fail "a missing provider is not required from options.lua" "$(cat "$nvim_options")"
pass "a missing provider writes nothing into the Neovim config"

# The tmux half of this migration stands on its own, so it still has to run for
# someone without the package.
grep -qF 'set -as terminal-features ",*:clipboard"' "$tmux_config" ||
  fail "a missing provider still gets the tmux clipboard feature" "$(cat "$tmux_config")"
pass "a missing provider still gets the tmux clipboard feature"

before=$(sha256sum "$tmux_config")
run_migration "$test_dir/share/absent.lua"
[[ $before == $(sha256sum "$tmux_config") ]] || fail "the tmux clipboard feature is added once" "$(cat "$tmux_config")"
pass "the tmux clipboard feature is added once"

# ------------------------------------------------------------- no Neovim config

reset_home
run_migration

[[ ! -e $nvim_config_dir ]] || fail "no Neovim config means no Neovim config is created"
pass "no Neovim config means no Neovim config is created"
