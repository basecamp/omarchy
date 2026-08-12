#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
socket="omarchy-tmux-config-$$"
migrated_socket="omarchy-tmux-migrated-$$"
trap 'tmux -L "$socket" kill-server 2>/dev/null || true; tmux -L "$migrated_socket" kill-server 2>/dev/null || true; rm -rf "$test_tmp"' EXIT

tmux -L "$socket" -f "$ROOT/config/tmux/tmux.conf" new-session -d

overrides=$(tmux -L "$socket" show-options -s terminal-overrides)
[[ $overrides == *'xterm*:Ms=\\E]52;c;%p2%s\\007'* ]] ||
  fail "tmux pins OSC 52 copies to the clipboard selector mosh accepts" "$overrides"
pass "tmux emits mosh-compatible OSC 52 clipboard sequences"

copy_binding=$(tmux -L "$socket" list-keys -T copy-mode-vi y)
[[ $copy_binding == *"omarchy-tmux-osc52-copy"* ]] ||
  fail "tmux copy mode bypasses cached terminal capabilities" "$copy_binding"
pass "tmux copy mode writes directly to the active client"

clipboard="$test_tmp/clipboard"
: >"$clipboard"
printf 'hello' | "$ROOT/bin/omarchy-tmux-osc52-copy" "$clipboard"
expected=$(printf '\033]52;c;aGVsbG8=\007')
[[ $(<"$clipboard") == "$expected" ]] ||
  fail "OSC 52 helper targets the system clipboard" "$(od -An -tx1 "$clipboard")"
pass "tmux clipboard helper emits a mosh-compatible sequence"

home="$test_tmp/home"
mkdir -p "$home/.config/tmux" "$test_tmp/bin"
printf '%s\n' \
  'set -g mouse on' \
  'bind -N "Copy selection" -T copy-mode-vi y send -X copy-selection-and-cancel' \
  >"$home/.config/tmux/tmux.conf"
printf '%s' 'set -g status off' >>"$home/.config/tmux/tmux.conf"

cat >"$test_tmp/bin/tmux" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TMUX_LOG"
[[ $1 == "list-sessions" || $1 == "source-file" ]]
SH

cat >"$test_tmp/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$test_tmp/bin/tmux" "$test_tmp/bin/omarchy-cmd-present"

migration="$ROOT/migrations/1786553531.sh"
tmux_log="$test_tmp/tmux.log"
HOME="$home" TMUX_LOG="$tmux_log" PATH="$test_tmp/bin:$PATH" bash -euo pipefail "$migration" >/dev/null

grep -Fq 'xterm*:Ms=\\E]52;c;%p2%s\\007' "$home/.config/tmux/tmux.conf" ||
  fail "tmux migration adds the mosh selector override"
grep -Fq 'omarchy-tmux-osc52-copy' "$home/.config/tmux/tmux.conf" ||
  fail "tmux migration adds direct copy bindings"
grep -Fqx 'set -g status off' "$home/.config/tmux/tmux.conf" ||
  fail "tmux migration preserves a final line without a newline"
grep -Fqx "source-file $home/.config/tmux/tmux.conf" "$tmux_log" ||
  fail "tmux migration reloads a running server"
pass "tmux migration updates existing configs and live servers"

tmux -L "$migrated_socket" -f "$home/.config/tmux/tmux.conf" new-session -d
migrated_overrides=$(tmux -L "$migrated_socket" show-options -s terminal-overrides)
[[ $migrated_overrides == *'xterm*:Ms=\\E]52;c;%p2%s\\007'* ]] ||
  fail "migrated tmux override parses like the packaged default" "$migrated_overrides"
pass "tmux migration writes a valid terminal capability"

before=$(sha256sum "$home/.config/tmux/tmux.conf")
HOME="$home" TMUX_LOG="$tmux_log" PATH="$test_tmp/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
[[ $before == $(sha256sum "$home/.config/tmux/tmux.conf") ]] ||
  fail "tmux clipboard migration is idempotent"
pass "tmux clipboard migration is idempotent"

custom_home="$test_tmp/custom-home"
mkdir -p "$custom_home/.config/tmux"
custom_binding='bind -T copy-mode-vi y send -X copy-pipe "custom-copy"'
printf '%s\n' 'set -g mouse on' "$custom_binding" >"$custom_home/.config/tmux/tmux.conf"
HOME="$custom_home" TMUX_LOG="$tmux_log" PATH="$test_tmp/bin:$PATH" bash -euo pipefail "$migration" >/dev/null

grep -Fqx "$custom_binding" "$custom_home/.config/tmux/tmux.conf" ||
  fail "tmux migration preserves a custom copy binding"
if grep -Fq 'omarchy-tmux-osc52-copy' "$custom_home/.config/tmux/tmux.conf"; then
  fail "tmux migration replaces a custom copy binding"
fi
pass "tmux migration leaves custom copy bindings alone"
