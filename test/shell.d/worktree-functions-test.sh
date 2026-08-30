#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/default/bash/fns/worktrees"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$tmp_dir--created"' EXIT

(
  cd "$tmp_dir"
  mise_called=0
  git() {
    return 128
  }
  mise() {
    mise_called=1
    return 0
  }

  if ga duplicate; then
    fail "ga reports a failed worktree creation"
  fi
  (( mise_called == 0 )) || fail "ga does not trust a worktree after creation fails"
  [[ $PWD == "$tmp_dir" ]] || fail "ga stays in the current directory after creation fails" "$PWD"
  pass "ga stops when worktree creation fails"
)

mkdir -p "$tmp_dir--created"
(
  cd "$tmp_dir"
  git() {
    return 0
  }
  mise() {
    return 0
  }

  ga created
  [[ $PWD == "$tmp_dir--created" ]] || fail "ga enters a successfully created worktree" "$PWD"
  pass "ga enters a successfully created worktree"
)
