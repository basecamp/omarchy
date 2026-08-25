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

# Same reasoning as omarchy-dns: the privileged half runs under sudo's
# secure_path, and a dev link prepends a user-writable checkout bin/ to it.
grep -Eq '^\s*export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin' "$helper" ||
  fail "omarchy-theme-set-browser-policy pins PATH to trusted system directories when it holds root"
gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$helper" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "omarchy-theme-set-browser-policy gates the trusted-PATH pin on holding root"

pass "browser policy sudoers rule is scoped to a single color argument"

# The directories are enterprise policy trust roots and the caller only ever
# picks a color, so the paths are fixed in the script. A path assembled from
# argv would let the grant write policy anywhere.
for dir in /etc/chromium/policies/managed /etc/opt/chrome/policies/managed \
  /etc/opt/edge/policies/managed /etc/brave/policies/managed; do
  grep -Fx "  $dir" "$helper" >/dev/null ||
    fail "omarchy-theme-set-browser-policy names $dir in its fixed policy directory list"
done

policy_dir_count=$(sed -n '/^POLICY_DIRS=(/,/^)/p' "$helper" | grep -c '^  /')
((policy_dir_count == 4)) ||
  fail "omarchy-theme-set-browser-policy writes only the four known policy directories" \
    "got: $policy_dir_count"

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

# The sudo stub plays both parts: it answers the passwordless probe according to
# STUB_GRANTED, and logs the elevation otherwise. STUB_GRANTED empty stands for
# an install whose omarchy-settings predates the sudoers file.
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

# Running as root skips require_root entirely, and the helper would then write
# this machine's real browser policy directories.
if ((EUID == 0)); then
  pass "running as root; skipping the elevation checks, which would rewrite this machine's browser policy"
  exit 0
fi

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

# A dev-linked checkout elevates the packaged path like everyone else, rather
# than handing sudo a path no rule can name and losing the grant.
dev_linked=$(OMARCHY_PATH="$test_tmp/checkout" elevation_for 1c2027)
[[ $dev_linked == "sudo /usr/bin/omarchy-theme-set-browser-policy 1c2027" ]] ||
  fail "omarchy-theme-set-browser-policy elevates the system install wherever OMARCHY_PATH points" \
    "got: $dev_linked"

pass "browser policy helper elevates a valid color through the sudo grant"

# Where the grant does not reach and there is no terminal, the helper leaves the
# policy alone. A browser accent color does not justify an authentication dialog
# on every theme switch, so this must not reach pkexec either.
ungranted=$(STUB_GRANTED="" elevation_for 1c2027)
[[ -z $ungranted ]] ||
  fail "omarchy-theme-set-browser-policy stays quiet where the grant does not reach" "got: $ungranted"

if ! STUB_GRANTED="" PATH="$stub_bin:$PATH" ELEVATION_LOG="$test_tmp/elevation" \
  bash "$helper" 1c2027 </dev/null >/dev/null 2>&1; then
  fail "omarchy-theme-set-browser-policy succeeds when it declines to elevate, so the rest of the theme applies"
fi

pass "browser policy helper skips the write rather than prompting where the grant is absent"

# Validation runs before any elevation, so a rejected argument never reaches
# sudo. Anything but six lowercase hex digits is rejected, and the sudoers glob
# independently refuses the same shapes.
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

# Two arguments, where each on its own would be valid.
if PATH="$stub_bin:$PATH" bash "$helper" 1c2027 ffffff </dev/null >/dev/null 2>&1; then
  fail "omarchy-theme-set-browser-policy rejects more than one argument"
fi

pass "browser policy helper accepts nothing but six lowercase hex digits"

# The color comes out of the current theme's chromium.theme, a file under the
# user's own state directory. A malformed or hostile one must land on the neutral
# fallback rather than reaching the policy writer as anything else.
setter_bin="$test_tmp/setter-bin"
mkdir -p "$setter_bin"

cat >"$setter_bin/omarchy-theme-set-browser-policy" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$COLOR_LOG"
SH
chmod +x "$setter_bin/omarchy-theme-set-browser-policy"

# No browser is "present", so the refresh half does nothing.
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
    bash "$setter" </dev/null >/dev/null 2>&1 || true
  cat "$test_tmp/color"
}

# A theme with no trailing newline is the common case in themes/.
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
    fail "omarchy-theme-set-browser falls back to the neutral color for '$malformed'" "got: $color"
done

[[ $(color_for_theme) == "1c2027" ]] ||
  fail "omarchy-theme-set-browser falls back to the neutral color with no theme file"

pass "browser theme color is derived as six hex digits or falls back to the neutral color"

# Nothing in the tree may reopen a browser policy directory. Check the bits each
# mode change actually sets rather than matching the one string that caused this
# bug, so a different spelling of the same mistake is caught too. Paths stay
# relative: an absolute checkout path can itself contain "policy" and would
# match every line.
policy_path='polic(y|ies)|distribution|/etc/chromium|/etc/brave|/etc/opt/(chrome|edge)'
offenders=()

while IFS= read -r line; do
  [[ $line =~ $policy_path ]] || continue

  # Symbolic forms that hand a write bit to group or other. u+w is not one.
  if [[ $line =~ chmod[^\&\|]*[ago]+\+[rx]*w ]]; then
    offenders+=("$line")
    continue
  fi

  if [[ $line =~ (chmod|-m)[[:space:]]+([0-7]{3,4}) ]]; then
    mode=${BASH_REMATCH[2]}
    if ((8#$mode & 022)); then
      offenders+=("$line")
    fi
  fi
done < <(cd "$ROOT" && grep -rnE 'chmod|install -d|install -m' bin install migrations 2>/dev/null)

((${#offenders[@]} == 0)) ||
  fail "no script opens a browser policy directory to other users" "got: ${offenders[*]}"

pass "no script makes a browser policy directory writable by other users"
