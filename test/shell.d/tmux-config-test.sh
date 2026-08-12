#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

socket="omarchy-tmux-config-$$"
trap 'tmux -L "$socket" kill-server 2>/dev/null || true' EXIT

tmux -L "$socket" -f "$ROOT/config/tmux/tmux.conf" new-session -d

overrides=$(tmux -L "$socket" show-options -s terminal-overrides)
[[ $overrides == *'xterm*:Ms=\\E]52;c;%p2%s\\007'* ]] ||
  fail "tmux pins OSC 52 copies to the clipboard selector mosh accepts" "$overrides"
pass "tmux emits mosh-compatible OSC 52 clipboard sequences"
