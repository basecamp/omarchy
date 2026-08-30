#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
export XDG_RUNTIME_DIR="$test_tmp/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

# Source the path helper the same way the scripts resolve it.
path_from_update=$(bash -c '
  omarchy_update_log_path() {
    local dir
    if [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && ! -L $XDG_RUNTIME_DIR ]]; then
      dir="$XDG_RUNTIME_DIR/omarchy-update"
    else
      dir="${HOME}/.cache/omarchy/update"
    fi
    mkdir -p -m 700 "$dir"
    printf "%s" "$dir/update.log"
  }
  omarchy_update_log_path
')

[[ $path_from_update == "$XDG_RUNTIME_DIR/omarchy-update/update.log" ]] ||
  fail "update log resolves under XDG_RUNTIME_DIR" "$path_from_update"
pass "update log resolves under XDG_RUNTIME_DIR"

# Analyze-logs must ignore a symlink at the log path (the attack /tmp used to allow).
mkdir -p "$XDG_RUNTIME_DIR/omarchy-update"
ln -s "$HOME/.bashrc" "$XDG_RUNTIME_DIR/omarchy-update/update.log"
touch "$HOME/.bashrc"
OMARCHY_UPDATE_LOG="$XDG_RUNTIME_DIR/omarchy-update/update.log" \
  bash "$ROOT/bin/omarchy-update-analyze-logs"
# Still a symlink — analyze refused to read it; bashrc untouched content-wise.
[[ -L $XDG_RUNTIME_DIR/omarchy-update/update.log ]] ||
  fail "analyze-logs must not replace a planted symlink"
pass "analyze-logs refuses to read a planted symlink"

# Without XDG_RUNTIME_DIR, fall back under $HOME/.cache, never /tmp.
unset XDG_RUNTIME_DIR
fallback=$(bash -c '
  omarchy_update_log_path() {
    local dir
    if [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && ! -L $XDG_RUNTIME_DIR ]]; then
      dir="$XDG_RUNTIME_DIR/omarchy-update"
    else
      dir="${HOME}/.cache/omarchy/update"
    fi
    mkdir -p -m 700 "$dir"
    printf "%s" "$dir/update.log"
  }
  omarchy_update_log_path
')
[[ $fallback == "$HOME/.cache/omarchy/update/update.log" ]] ||
  fail "update log falls back under \$HOME/.cache" "$fallback"
[[ $fallback != /tmp/* ]] || fail "update log must not fall back under /tmp" "$fallback"
pass "update log falls back under \$HOME/.cache, not /tmp"

if grep -E '^[^#]* /tmp/omarchy-update\.log' "$ROOT/bin/omarchy-update" >/dev/null; then
  fail "omarchy-update still hard-codes /tmp/omarchy-update.log"
fi
pass "omarchy-update no longer hard-codes /tmp/omarchy-update.log"
