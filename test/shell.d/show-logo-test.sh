#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

omarchy_path="$tmp/omarchy"
home="$tmp/home"
theme_dir="$home/.local/state/omarchy/current/theme"
mkdir -p "$omarchy_path" "$theme_dir" "$tmp/bin"

cp "$ROOT/logo.txt" "$omarchy_path/logo.txt"

# clear dumps terminfo into the capture; the colour is what this file pins.
printf '#!/bin/bash\n' >"$tmp/bin/clear"
chmod +x "$tmp/bin/clear"

# omarchy-theme-color needs bash 4 associative arrays. Invoke it with this
# test's bash rather than the shebang, so the suite can run where /bin/bash is older.
printf '#!/bin/bash\nexec %q %q "$@"\n' "$BASH" "$ROOT/bin/omarchy-theme-color" >"$tmp/bin/omarchy-theme-color"
chmod +x "$tmp/bin/omarchy-theme-color"

run_logo() {
  HOME="$home" OMARCHY_PATH="$omarchy_path" PATH="$tmp/bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-show-logo"
}

logo_art=$(cat "$ROOT/logo.txt")

# #9ece6a — Tokyo Night green, and not the stock ANSI 32.
cat >"$theme_dir/colors.toml" <<'TOML'
green = "#9ece6a"
accent = "#7aa2f7"
TOML

output=$(run_logo)
green_sgr=$'\033[38;2;158;206;106m'
[[ $output == *"$green_sgr"* ]] || fail "logo uses the theme's green" "$(printf '%q' "$output")"
[[ $output == *$'\033[0m'* ]] || fail "logo resets the colour" "$(printf '%q' "$output")"
[[ $output == *"$logo_art"* ]] || fail "logo art is the wordmark from logo.txt"
pass "logo uses the theme's green"

# green wins when both keys are present; accent is the fallback when it is not.
cat >"$theme_dir/colors.toml" <<'TOML'
accent = "#bb9af7"
TOML

output=$(run_logo)
accent_sgr=$'\033[38;2;187;154;247m'
[[ $output == *"$accent_sgr"* ]] || fail "logo falls back to the theme's accent" "$(printf '%q' "$output")"
pass "logo falls back to the theme's accent"

rm -rf "$theme_dir"
output=$(run_logo)
[[ $output == *$'\033[32m'* ]] || fail "missing theme falls back to ANSI 32" "$(printf '%q' "$output")"
[[ $output != *$'\033[38;2;'* ]] || fail "missing theme does not emit truecolor" "$(printf '%q' "$output")"
[[ $output == *$'\033[0m'* ]] || fail "fallback still resets the colour" "$(printf '%q' "$output")"
[[ $output == *"$logo_art"* ]] || fail "fallback still draws the wordmark from logo.txt"
pass "missing theme falls back to ANSI 32"
