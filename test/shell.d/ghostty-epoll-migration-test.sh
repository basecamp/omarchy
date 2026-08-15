#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1786790068.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
ghostty_config="$home/.config/ghostty/config"
workaround_comment="# Fix general slowness on hyprland (https://github.com/ghostty-org/ghostty/discussions/3224)"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

reset_config() {
  mkdir -p "$(dirname "$ghostty_config")"
  cp "$ROOT/config/ghostty/config" "$ghostty_config"
}

reset_config
printf '\n%s\n%s\n' "$workaround_comment" 'async-backend = epoll' >>"$ghostty_config"

run_migration

grep -qxF "$workaround_comment" "$ghostty_config" &&
  fail "migration removes the Omarchy Ghostty workaround comment"
grep -qxF 'async-backend = epoll' "$ghostty_config" &&
  fail "migration removes the Omarchy Ghostty epoll setting"
pass "migration removes the shipped Ghostty epoll workaround"

before=$(sha256sum "$ghostty_config")
run_migration
[[ $before == $(sha256sum "$ghostty_config") ]] || fail "Ghostty epoll migration is idempotent"
pass "Ghostty epoll migration is idempotent"

reset_config
printf '\n%s\n' 'async-backend = epoll' >>"$ghostty_config"
run_migration
grep -qxF 'async-backend = epoll' "$ghostty_config" ||
  fail "migration preserves an independently configured epoll backend"
pass "migration preserves an independently configured epoll backend"

reset_config
printf '\n%s\n%s\n' "$workaround_comment" 'async-backend = io_uring' >>"$ghostty_config"
before=$(sha256sum "$ghostty_config")
run_migration
[[ $before == $(sha256sum "$ghostty_config") ]] ||
  fail "migration preserves a customized Omarchy backend stanza"
pass "migration preserves a customized Omarchy backend stanza"

mkdir -p "$home/dotfiles"
cp "$ROOT/config/ghostty/config" "$home/dotfiles/ghostty-config"
printf '\n%s\n%s\n' "$workaround_comment" 'async-backend = epoll' >>"$home/dotfiles/ghostty-config"
ln -sfn "$home/dotfiles/ghostty-config" "$ghostty_config"

run_migration

[[ -L $ghostty_config ]] || fail "migration preserves a symlinked Ghostty config"
grep -qxF 'async-backend = epoll' "$home/dotfiles/ghostty-config" &&
  fail "migration cleans the symlinked Ghostty config target"
pass "migration writes through a symlinked Ghostty config"
