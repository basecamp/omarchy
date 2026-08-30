#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

helper="$ROOT/bin/omarchy-theme-set-browser-policy"
setter="$ROOT/bin/omarchy-theme-set-browser"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-theme-browser"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-theme-set-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'

# Exactly one rule, matched whole. Dropping the argument -- which sudoers reads
# as "any arguments" -- or widening the glob to `*` would let the grant carry
# something other than a color while leaving this line looking right.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "browser policy sudoers file carries exactly the six-hex-digit rule and nothing else" "got: $rules"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "browser policy sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-theme-set-browser-policy' "$helper" >/dev/null ||
  fail "omarchy-theme-set-browser-policy elevates the path the sudoers rule names"

grep -E 'sudo -n -l -l' "$helper" >/dev/null ||
  fail "omarchy-theme-set-browser-policy reads the grant from the long sudo listing"

grep -Eq '^\s*export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin' "$helper" ||
  fail "omarchy-theme-set-browser-policy pins PATH to trusted system directories when it holds root"
gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$helper" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "omarchy-theme-set-browser-policy gates the trusted-PATH pin on holding root"

pass "browser policy sudoers rule is scoped to a single color argument"

for dir in /etc/chromium/policies/managed /etc/opt/chrome/policies/managed \
  /etc/opt/edge/policies/managed /etc/brave/policies/managed; do
  grep -Fx "  $dir" "$helper" >/dev/null ||
    fail "omarchy-theme-set-browser-policy names $dir in its fixed policy directory list"
done

policy_dir_count=$(sed -n '/^POLICY_DIRS=(/,/^)/p' "$helper" | grep -c '^  /')
((policy_dir_count == 4)) ||
  fail "omarchy-theme-set-browser-policy writes only the four known policy directories" \
    "got: $policy_dir_count"

grep -F 'install -m 0644 -o root -g root -T' "$helper" >/dev/null ||
  fail "omarchy-theme-set-browser-policy installs color.json with install -T"
if grep -E 'mv -f' "$helper" >/dev/null; then
  fail "omarchy-theme-set-browser-policy does not mv into a planted color.json directory"
fi

pass "browser policy helper writes a fixed set of policy directories"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/pkexec"

# STUB_GRANTED empty stands for an install whose omarchy-settings predates the
# sudoers file. The default is granted, matching a current Omarchy.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l ]]; then
  if [[ ${STUB_GRANTED-granted} == "granted" ]]; then
    echo "    Options: !authenticate"
  else
    echo "    Matched: ${!#}"
  fi
  exit 0
fi
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

if ((EUID == 0)); then
  pass "running as root; skipping the elevation checks, which would rewrite this machine's browser policy"
else
  elevation_for() {
    : >"$test_tmp/elevation"
    ELEVATION_LOG="$test_tmp/elevation" \
      PATH="$stub_bin:$PATH" \
      bash "$helper" "$@" </dev/null >/dev/null 2>&1 || true
    cat "$test_tmp/elevation"
  }

  elevation=$(elevation_for 1c2027)
  [[ $elevation == "sudo /usr/bin/omarchy-theme-set-browser-policy 1c2027" ]] ||
    fail "omarchy-theme-set-browser-policy takes the passwordless sudo grant without a terminal" \
      "got: $elevation"

  dev_linked=$(OMARCHY_PATH="$test_tmp/checkout" elevation_for 1c2027)
  [[ $dev_linked == "sudo /usr/bin/omarchy-theme-set-browser-policy 1c2027" ]] ||
    fail "omarchy-theme-set-browser-policy elevates the system install wherever OMARCHY_PATH points" \
      "got: $dev_linked"

  pass "browser policy helper elevates a valid color through the sudo grant"

  ungranted=$(STUB_GRANTED="" elevation_for 1c2027)
  [[ $ungranted == "pkexec /usr/bin/omarchy-theme-set-browser-policy 1c2027" ]] ||
    fail "omarchy-theme-set-browser-policy falls back to polkit where the grant does not reach" \
      "got: $ungranted"

  pass "browser policy helper falls back to polkit wherever the grant does not reach"

  for bad in "" "1C2027" "abc12" "abc1234" "1c202g" "../../etc/passwd" "1c2027 1c2027" \
    '$(id)' "1c2027;id" "#1c2027"; do
    if PATH="$stub_bin:$PATH" ELEVATION_LOG="$test_tmp/elevation" \
      bash "$helper" "$bad" </dev/null >/dev/null 2>&1; then
      fail "omarchy-theme-set-browser-policy rejects '$bad'"
    fi

    rejected=$(elevation_for "$bad")
    [[ -z $rejected ]] ||
      fail "omarchy-theme-set-browser-policy rejects '$bad' before elevating" "got: $rejected"
  done

  if PATH="$stub_bin:$PATH" bash "$helper" 1c2027 ffffff </dev/null >/dev/null 2>&1; then
    fail "omarchy-theme-set-browser-policy rejects more than one argument"
  fi

  pass "browser policy helper accepts nothing but six lowercase hex digits"
fi

setter_bin="$test_tmp/setter-bin"
mkdir -p "$setter_bin"

cat >"$setter_bin/omarchy-theme-set-browser-policy" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$COLOR_LOG"
SH
chmod +x "$setter_bin/omarchy-theme-set-browser-policy"

cat >"$setter_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$setter_bin/omarchy-cmd-present"

setter_home="$test_tmp/home"
theme_dir="$setter_home/.local/state/omarchy/current/theme"
mkdir -p "$theme_dir"

color_for_theme() {
  : >"$test_tmp/color"
  if [[ $# -gt 0 ]]; then
    printf '%s' "$1" >"$theme_dir/chromium.theme"
  else
    rm -f "$theme_dir/chromium.theme"
  fi

  HOME="$setter_home" COLOR_LOG="$test_tmp/color" PATH="$setter_bin:$stub_bin:$PATH" \
    OMARCHY_PATH="$ROOT" bash "$setter" </dev/null >/dev/null 2>&1 || true
  cat "$test_tmp/color"
}

[[ $(color_for_theme "242,240,229") == "f2f0e5" ]] ||
  fail "omarchy-theme-set-browser converts an RGB triple to six hex digits"
[[ $(color_for_theme $'14,31,41\n') == "0e1f29" ]] ||
  fail "omarchy-theme-set-browser accepts a trailing newline"
[[ $(color_for_theme "0,0,0") == "000000" ]] ||
  fail "omarchy-theme-set-browser pads single-digit components"
[[ $(color_for_theme " 12 , 11 , 12 ") == "0c0b0c" ]] ||
  fail "omarchy-theme-set-browser tolerates surrounding whitespace"

for malformed in "" "not,a,color" "1,2" "1,2,3,4" "256,0,0" "999,999,999" "-1,0,0" \
  "1,2,3;id" '1,2,$(id)' "0x10,0,0" "1,2,3 4,5,6"; do
  color=$(color_for_theme "$malformed")
  [[ $color == "1c2027" ]] ||
    fail "omarchy-theme-set-browser falls back to the stock colour for '$malformed'" "got: $color"
done

[[ $(color_for_theme) == "1c2027" ]] ||
  fail "omarchy-theme-set-browser falls back to the stock colour with no theme file"

pass "browser theme color is derived as six hex digits or falls back to the stock grey"
