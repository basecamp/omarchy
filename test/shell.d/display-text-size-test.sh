#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub_bin="$tmpdir/bin"
mkdir -p "$home/.config/ghostty" "$home/.config/alacritty" \
  "$home/.config/kitty" "$home/.config/foot" "$stub_bin"

cat >"$home/.config/ghostty/config" <<'EOF'
font-size = 11
EOF
cat >"$home/.config/alacritty/alacritty.toml" <<'EOF'
size = 12
EOF
cat >"$home/.config/kitty/kitty.conf" <<'EOF'
font_size 13.0
EOF
cat >"$home/.config/foot/foot.ini" <<'EOF'
font=JetBrainsMono:size=9.5
EOF

cat >"$stub_bin/omarchy-default-terminal" <<'SH'
#!/bin/bash
echo "$TEST_TERMINAL"
SH
chmod +x "$stub_bin/omarchy-default-terminal"

cat >"$stub_bin/gsettings" <<'SH'
#!/bin/bash
echo 1.0
SH
chmod +x "$stub_bin/gsettings"

reported_size() {
  TEST_TERMINAL="$1" HOME="$home" PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-display-text-size" | sed -n 's/^terminal font: \(.*\) pt$/\1/p'
}

[[ $(reported_size foot) == "9.5" ]] ||
  fail "text size reads the selected Foot config" "$(reported_size foot)"
pass "text size reads the selected Foot config"

[[ $(reported_size alacritty) == "12" ]] ||
  fail "text size reads the selected Alacritty config" "$(reported_size alacritty)"
pass "text size reads the selected Alacritty config"

[[ $(reported_size kitty) == "13.0" ]] ||
  fail "text size reads the selected Kitty config" "$(reported_size kitty)"
pass "text size reads the selected Kitty config"

[[ $(reported_size ghostty) == "11" ]] ||
  fail "text size reads the selected Ghostty config" "$(reported_size ghostty)"
pass "text size reads the selected Ghostty config"
