#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/xdg-terminal-exec" <<'SCRIPT'
#!/bin/bash
if [[ $1 == --print-id ]]; then
  printf '%s\n' "$OMARCHY_TEST_TERMINAL_ID"
  exit 0
fi
exit 0
SCRIPT

cat >"$tmp_dir/bin/hyprctl" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
exit 0
SCRIPT

cat >"$tmp_dir/bin/setsid" <<'SCRIPT'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

chmod +x "$tmp_dir/bin/"*

launch() {
  TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-launch-tui" "$@"
}

# TUI windows run under their own app id, so the per-terminal scroll_touchpad
# rules never reach them — agent windows included — and a fullscreen TUI also
# misses foot's scrollback multiplier. The launcher sizes a one-off rule to
# the terminal it is about to run, so a TUI scrolls like a regular terminal.
for pair in "foot.desktop:10" "ghostty.desktop:0.2" "kitty.desktop:1.5"; do
  terminal=${pair%%:*}
  multiplier=${pair##*:}
  : >"$tmp_dir/log"
  OMARCHY_TEST_TERMINAL_ID="$terminal" launch --app-id=org.omarchy.agent claude
  grep -Fq 'match = { class = [[^org.omarchy.agent$]] }' "$tmp_dir/log" ||
    fail "the agent TUI gets a scroll rule for $terminal"
  grep -Fq "scroll_touchpad = $multiplier" "$tmp_dir/log" ||
    fail "the $terminal agent TUI scrolls like a regular terminal" "$(cat "$tmp_dir/log")"
done
pass "the agent TUI scrolls like a regular terminal"

# The same defect reaches every TUI launch (the window's class is not a
# terminal), so the rule is not agent-specific: htop under foot scrolls like
# a regular terminal too.
: >"$tmp_dir/log"
OMARCHY_TEST_TERMINAL_ID="foot.desktop" launch htop
grep -Fq 'class = [[^org.omarchy.htop$]]' "$tmp_dir/log" ||
  fail "other TUIs keep scrolling like a regular terminal" "$(cat "$tmp_dir/log")"
grep -Fq 'scroll_touchpad = 10' "$tmp_dir/log" ||
  fail "other TUIs keep scrolling like a regular terminal" "$(cat "$tmp_dir/log")"
pass "other TUIs keep scrolling like a regular terminal"