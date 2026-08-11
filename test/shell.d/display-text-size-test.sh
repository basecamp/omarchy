#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"

mkdir -p "$stub_bin" "$home_dir/.config"/{ghostty,alacritty,kitty,foot}

cat >"$stub_bin/omarchy-default-terminal" <<'SH'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_DEFAULT_TERMINAL:-}"
SH

cat >"$stub_bin/gsettings" <<'SH'
#!/bin/bash
[[ $1 == "get" ]] && printf "1.0\n"
exit 0
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

# Every terminal is configured, at a different size, so a report naming the
# wrong one is unambiguous.
printf 'font-size = 9\n' >"$home_dir/.config/ghostty/config"
printf 'size = 10\n' >"$home_dir/.config/alacritty/alacritty.toml"
printf 'font_size 11.0\n' >"$home_dir/.config/kitty/kitty.conf"
printf 'font=JetBrainsMono Nerd Font:size=12\n' >"$home_dir/.config/foot/foot.ini"

run_text_size() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_DEFAULT_TERMINAL="${OMARCHY_TEST_DEFAULT_TERMINAL:-}" \
    "$ROOT/bin/omarchy-display-text-size" "$@"
}

reported_pt() {
  run_text_size | sed -n 's/^terminal font: \([0-9.]*\) pt$/\1/p'
}

# --- the report follows the terminal in use ---

[[ $(OMARCHY_TEST_DEFAULT_TERMINAL=foot reported_pt) == "12" ]] ||
  fail "reports foot's size when foot is the default terminal"
[[ $(OMARCHY_TEST_DEFAULT_TERMINAL=kitty reported_pt) == "11.0" ]] ||
  fail "reports kitty's size when kitty is the default terminal"
[[ $(OMARCHY_TEST_DEFAULT_TERMINAL=alacritty reported_pt) == "10" ]] ||
  fail "reports alacritty's size when alacritty is the default terminal"
[[ $(OMARCHY_TEST_DEFAULT_TERMINAL=ghostty reported_pt) == "9" ]] ||
  fail "reports ghostty's size when ghostty is the default terminal"
pass "the reported terminal size follows the terminal actually in use"

# --- falling back when the default cannot be resolved ---

[[ $(OMARCHY_TEST_DEFAULT_TERMINAL= reported_pt) == "9" ]] ||
  fail "falls back to the first configured terminal when the default is unknown"
pass "an unresolvable default terminal falls back to the first configured one"

# A default naming a terminal with no config here is no better than no answer.
[[ $(OMARCHY_TEST_DEFAULT_TERMINAL=wezterm reported_pt) == "9" ]] ||
  fail "falls back when the default terminal has no config"
pass "a default terminal without a config falls back too"

# --- writes still reach every terminal, since the default can change later ---

OMARCHY_TEST_DEFAULT_TERMINAL=foot run_text_size 16 >/dev/null 2>&1
grep -Fx 'font-size = 12' "$home_dir/.config/ghostty/config" >/dev/null ||
  fail "setting a size writes ghostty even when foot is the default"
grep -Fx 'size = 12' "$home_dir/.config/alacritty/alacritty.toml" >/dev/null ||
  fail "setting a size writes alacritty even when foot is the default"
grep -Fx 'font_size 12.0' "$home_dir/.config/kitty/kitty.conf" >/dev/null ||
  fail "setting a size writes kitty even when foot is the default"
grep -F ':size=12' "$home_dir/.config/foot/foot.ini" >/dev/null ||
  fail "setting a size writes foot"
pass "setting a size writes every terminal config, not just the default"

# --- reset returns every surface to its default ---

OMARCHY_TEST_DEFAULT_TERMINAL=foot run_text_size reset >/dev/null 2>&1
[[ $(grep -oP ':size=\K[0-9.]+' "$home_dir/.config/foot/foot.ini") == "9" ]] ||
  fail "reset returns the terminal to its default size"
pass "reset returns every surface to its default"

# --- the ratio holds regardless of what a terminal was set to ---

rm -f "$home_dir/.config"/{ghostty/config,alacritty/alacritty.toml,kitty/kitty.conf,foot/foot.ini}
printf 'font=JetBrainsMono Nerd Font:size=9\n' >"$home_dir/.config/foot/foot.ini"
OMARCHY_TEST_DEFAULT_TERMINAL=foot run_text_size 16 >/dev/null 2>&1
[[ $(grep -oP ':size=\K[0-9.]+' "$home_dir/.config/foot/foot.ini") == "12" ]] ||
  fail "a terminal takes the size the ratio gives it"
pass "a terminal takes the size the ratio gives it, whatever it was before"
