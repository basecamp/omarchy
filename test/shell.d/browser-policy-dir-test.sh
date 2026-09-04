#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export OMARCHY_PATH="$ROOT"
export OMARCHY_PROVISIONING_DIR="$test_tmp/provisioning"

source "$ROOT/install/helpers/browser-policy.sh"

# Temp dirs are user-owned; drop -o/-g so install(1) can run unprivileged.
unprivileged_as_root() {
  if [[ $1 == "install" ]]; then
    shift
    local args=()
    local skip=0
    local arg
    for arg in "$@"; do
      if (( skip )); then
        skip=0
        continue
      fi
      case $arg in
        -o|-g) skip=1 ;;
        *) args+=("$arg") ;;
      esac
    done
    command install "${args[@]}"
  else
    "$@"
  fi
}

write_dir=$test_tmp/writable
mkdir -p "$write_dir"
browser_policy_install_color "$write_dir" "#aabbcc" ||
  fail "theme colour writes into a writable policy directory"
grep -F '"BrowserThemeColor": "#aabbcc"' "$write_dir/color.json" >/dev/null ||
  fail "theme colour writes BrowserThemeColor"
mode=$(stat -c '%a' "$write_dir/color.json")
[[ $mode == "644" ]] || fail "theme colour creates a root-mode policy file" "mode=$mode"
pass "theme colour writes a 0644 color.json"

if (( EUID == 0 )); then
  pass "running as root; skipping the mktemp-failure check"
else
  chmod u+w "$write_dir"
  export TMPDIR=$test_tmp/missing-tmp
  if browser_policy_install_color "$write_dir" "#dead00" 2>/dev/null; then
    fail "theme colour fails when mktemp cannot create a file"
  fi
  unset TMPDIR
  grep -F '"BrowserThemeColor": "#aabbcc"' "$write_dir/color.json" >/dev/null ||
    fail "a failed mktemp leaves an existing color.json intact"
  pass "a failed mktemp does not truncate color.json"
fi

printf 'original\n' >"$test_tmp/pwn"
rm -f "$write_dir/color.json"
ln -s "$test_tmp/pwn" "$write_dir/color.json"
browser_policy_install_color "$write_dir" "#aabbcc" ||
  fail "theme colour replaces a planted color.json symlink"
[[ -f $write_dir/color.json && ! -L $write_dir/color.json ]] ||
  fail "theme colour unlinks a planted color.json symlink instead of writing through it"
grep -Fxq 'original' "$test_tmp/pwn" || fail "theme colour leaves the symlink target unchanged"
pass "theme colour does not follow a planted color.json symlink"

plant_write=$test_tmp/plant-dir
mkdir -p "$plant_write/color.json/nested"
printf 'inside\n' >"$plant_write/color.json/nested/x"
browser_policy_install_color "$plant_write" "#aabbcc" ||
  fail "theme colour replaces a planted color.json directory"
[[ -f $plant_write/color.json && ! -d $plant_write/color.json ]] ||
  fail "theme colour does not write into a planted color.json directory"
pass "theme colour does not write into a planted color.json directory"

missing_dir=$test_tmp/missing
browser_policy_install_color "$missing_dir" "#aabbcc" ||
  fail "theme colour skips a policy directory that does not exist"
[[ ! -e $missing_dir ]] || fail "theme colour does not create a missing policy directory"
pass "theme colour skips a missing policy directory"

if browser_policy_install_color "$write_dir" "aabbcc" 2>/dev/null; then
  fail "theme colour rejects hex without a leading #"
fi
if browser_policy_install_color "$write_dir" "#AABBCC" 2>/dev/null; then
  fail "theme colour rejects uppercase hex"
fi
pass "theme colour accepts only # plus six lowercase hex digits"

planted_dir=$test_tmp/planted
mkdir -p "$planted_dir/evil"
printf 'evil\n' >"$planted_dir/evil/f"
printf 'old\n' >"$planted_dir/color.json"
as_root() { unprivileged_as_root "$@"; }
browser_policy_setup_dir "$planted_dir"
[[ ! -e $planted_dir/evil ]] || fail "policy setup drops a non-empty non-root subdirectory"
[[ ! -e $planted_dir/color.json ]] || fail "policy setup drops a non-root color.json"
[[ -d $planted_dir ]] || fail "policy setup leaves the managed directory in place"
mode=$(stat -c '%a' "$planted_dir")
[[ $mode == "755" ]] || fail "policy setup leaves the managed directory 0755" "mode=$mode"
pass "policy setup drops non-root files and non-empty subdirectories"

owned=$test_tmp/not-root
mkdir -p "$owned"
chmod 755 "$owned"
if browser_policy_dir_hardened "$owned"; then
  fail "a user-owned 0755 directory is not treated as hardened"
fi
pass "a hardened directory must be root-owned"

saved_parent_dirs=("${BROWSER_POLICY_PARENT_DIRS[@]}")
parent_root=$test_tmp/parents
mkdir -p "$parent_root/etc/chromium/policies/managed/keep"
printf 'keep\n' >"$parent_root/etc/chromium/policies/managed/keep/x"
chmod 0777 "$parent_root/etc/chromium" "$parent_root/etc/chromium/policies"
chmod 755 "$parent_root/etc/chromium/policies/managed"
BROWSER_POLICY_PARENT_DIRS=(
  "$parent_root/etc/chromium"
  "$parent_root/etc/chromium/policies"
)
as_root() { unprivileged_as_root "$@"; }
if browser_policy_parents_hardened "$parent_root/etc/chromium/policies/managed"; then
  fail "a world-writable policy parent is not treated as hardened"
fi
browser_policy_setup_parents_for "$parent_root/etc/chromium/policies/managed"
mode=$(stat -c '%a' "$parent_root/etc/chromium")
[[ $mode == "755" ]] || fail "setup tightens /etc/chromium" "mode=$mode"
mode=$(stat -c '%a' "$parent_root/etc/chromium/policies")
[[ $mode == "755" ]] || fail "setup tightens /etc/chromium/policies" "mode=$mode"
[[ -d $parent_root/etc/chromium/policies/managed/keep ]] ||
  fail "parent repair does not purge the managed directory"
pass "policy parent directories are tightened to 0755 without purging the leaf"

symlink_root=$test_tmp/symlink-parents
mkdir -p "$symlink_root/etc" "$symlink_root/attacker/policies/managed"
printf 'planted\n' >"$symlink_root/attacker/policies/managed/evil.json"
ln -s "$symlink_root/attacker" "$symlink_root/etc/chromium"
BROWSER_POLICY_PARENT_DIRS=(
  "$symlink_root/etc/chromium"
  "$symlink_root/etc/chromium/policies"
)
as_root() { unprivileged_as_root "$@"; }
browser_policy_setup_dir "$symlink_root/etc/chromium/policies/managed"
[[ ! -L $symlink_root/etc/chromium ]] || fail "setup replaces a planted /etc/chromium symlink"
[[ -d $symlink_root/etc/chromium && ! -L $symlink_root/etc/chromium ]] ||
  fail "setup recreates /etc/chromium as a real directory"
[[ -d $symlink_root/etc/chromium/policies && ! -L $symlink_root/etc/chromium/policies ]] ||
  fail "setup recreates /etc/chromium/policies as a real directory"
[[ ! -e $symlink_root/etc/chromium/policies/managed/evil.json ]] ||
  fail "setup does not keep policy that lived behind a planted parent symlink"
grep -Fxq 'planted' "$symlink_root/attacker/policies/managed/evil.json" ||
  fail "replacing a parent symlink does not delete the symlink target"
BROWSER_POLICY_PARENT_DIRS=("${saved_parent_dirs[@]}")
pass "policy setup does not follow a planted parent symlink"

leaf_link_root=$test_tmp/leaf-link
mkdir -p "$leaf_link_root/etc/chromium/policies" "$leaf_link_root/attacker"
printf 'planted\n' >"$leaf_link_root/attacker/evil.json"
chmod 755 "$leaf_link_root/etc/chromium" "$leaf_link_root/etc/chromium/policies"
ln -s "$leaf_link_root/attacker" "$leaf_link_root/etc/chromium/policies/managed"
BROWSER_POLICY_PARENT_DIRS=(
  "$leaf_link_root/etc/chromium"
  "$leaf_link_root/etc/chromium/policies"
)
as_root() { unprivileged_as_root "$@"; }
if browser_policy_dir_hardened "$leaf_link_root/etc/chromium/policies/managed"; then
  fail "a planted managed symlink is not treated as hardened"
fi
browser_policy_setup_dir "$leaf_link_root/etc/chromium/policies/managed"
[[ ! -L $leaf_link_root/etc/chromium/policies/managed ]] ||
  fail "setup replaces a planted managed symlink"
[[ -d $leaf_link_root/etc/chromium/policies/managed && ! -L $leaf_link_root/etc/chromium/policies/managed ]] ||
  fail "setup recreates managed as a real directory"
[[ ! -e $leaf_link_root/etc/chromium/policies/managed/evil.json ]] ||
  fail "setup does not keep policy that lived behind a planted managed symlink"
grep -Fxq 'planted' "$leaf_link_root/attacker/evil.json" ||
  fail "replacing a managed symlink does not delete the symlink target"
BROWSER_POLICY_PARENT_DIRS=("${saved_parent_dirs[@]}")
pass "policy setup does not follow a planted managed symlink"

fx_link_root=$test_tmp/fx-link
mkdir -p "$fx_link_root/attacker" "$fx_link_root/opt"
printf 'planted\n' >"$fx_link_root/attacker/policies.json"
ln -s "$fx_link_root/attacker" "$fx_link_root/opt/zen"
as_root() { unprivileged_as_root "$@"; }
if browser_policy_firefox_hardened "$fx_link_root/opt/zen"; then
  fail "a planted Firefox distribution symlink is not treated as hardened"
fi
browser_policy_setup_firefox_distribution "$fx_link_root/opt/zen" ||
  fail "Firefox setup replaces a planted distribution symlink"
[[ ! -L $fx_link_root/opt/zen ]] || fail "Firefox setup unlinks a planted distribution symlink"
[[ -d $fx_link_root/opt/zen && ! -L $fx_link_root/opt/zen ]] ||
  fail "Firefox setup recreates the distribution directory"
[[ -f $fx_link_root/opt/zen/policies.json && ! -L $fx_link_root/opt/zen/policies.json ]] ||
  fail "Firefox setup writes policies.json into the recreated directory"
grep -Fxq 'planted' "$fx_link_root/attacker/policies.json" ||
  fail "replacing a Firefox distribution symlink does not delete the symlink target"
pass "Firefox setup does not follow a planted distribution symlink"

[[ $(browser_policy_theme_hex "242,240,229") == "#f2f0e5" ]] ||
  fail "theme colour converts an RGB triple to hex"
[[ $(browser_policy_theme_hex $'14,31,41\n') == "#0e1f29" ]] ||
  fail "theme colour accepts a trailing newline"
[[ $(browser_policy_theme_hex "0,0,0") == "#000000" ]] ||
  fail "theme colour pads single-digit components"
[[ $(browser_policy_theme_hex " 12 , 11 , 12 ") == "#0c0b0c" ]] ||
  fail "theme colour tolerates surrounding whitespace"
[[ $(browser_policy_theme_hex "08,09,10") == "#08090a" ]] ||
  fail "theme colour treats leading zeros as decimal"
for malformed in "" "not,a,color" "1,2" "1,2,3,4" "256,0,0" "999,999,999" "-1,0,0" \
  "1,2,3;id" '1,2,$(id)' "0x10,0,0" "1,2,3 4,5,6"; do
  [[ $(browser_policy_theme_hex "$malformed") == "#1c2027" ]] ||
    fail "theme colour falls back to the stock grey for '$malformed'"
done
pass "theme colour is six hex digits or the stock grey"

for theme in "$ROOT"/themes/*/chromium.theme; do
  [[ -f $theme ]] || continue
  rgb=$(<$theme)
  hex=$(browser_policy_theme_hex "$rgb")
  [[ $hex =~ ^#[0-9a-f]{6}$ ]] ||
    fail "shipped $(basename "$(dirname "$theme")") chromium.theme parses as hex" "got: $hex from $(printf %q "$rgb")"
  if [[ $hex == "#1c2027" && ! $rgb =~ ^[[:space:]]*28[[:space:]]*,[[:space:]]*32[[:space:]]*,[[:space:]]*39[[:space:]]*$ ]]; then
    fail "shipped $(basename "$(dirname "$theme")") chromium.theme is a valid RGB triple" "got: $(printf %q "$rgb")"
  fi
done
pass "shipped chromium.theme files parse as RGB triples"

grep -F 'browser_policy_theme_hex' "$ROOT/bin/omarchy-theme-set-browser" >/dev/null ||
  fail "omarchy-theme-set-browser parses chromium.theme through browser_policy_theme_hex"
grep -F 'omarchy-theme-set-browser-policy' "$ROOT/bin/omarchy-theme-set-browser" >/dev/null ||
  fail "omarchy-theme-set-browser writes colour through omarchy-theme-set-browser-policy"
if grep -E 'printf.*THEME_RGB_COLOR' "$ROOT/bin/omarchy-theme-set-browser" >/dev/null; then
  fail "omarchy-theme-set-browser does not hand unvetted theme words to printf"
fi
pass "omarchy-theme-set-browser validates the theme colour"

fx_policy=$test_tmp/policies.json
printf '%s\n' '{"policies":{}}' >"$fx_policy"
chmod 644 "$fx_policy"
if browser_policy_firefox_policy_file_ok "$fx_policy"; then
  fail "a user-owned policies.json is not treated as hardened"
fi
ln -sf "$fx_policy" "$test_tmp/policies-link.json"
if browser_policy_firefox_policy_file_ok "$test_tmp/policies-link.json"; then
  fail "a policies.json symlink is not treated as hardened"
fi
pass "Firefox policy files must be root-owned regular files without group or other write"

dist=$test_tmp/distribution
mkdir -p "$dist"
printf 'original\n' >"$test_tmp/firefox-pwn"
ln -s "$test_tmp/firefox-pwn" "$dist/policies.json"
as_root() { unprivileged_as_root "$@"; }
browser_policy_install_firefox_policies "$dist" ||
  fail "Firefox policy install replaces a planted policies.json symlink"
[[ -f $dist/policies.json && ! -L $dist/policies.json ]] ||
  fail "Firefox policy install unlinks a planted policies.json symlink instead of writing through it"
grep -Fxq 'original' "$test_tmp/firefox-pwn" || fail "Firefox policy install leaves the symlink target unchanged"
grep -q '"policies"' "$dist/policies.json" || fail "Firefox policy install writes the stock policies"
pass "Firefox policy install does not follow a planted policies.json symlink"

dir_dist=$test_tmp/distribution-dir
mkdir -p "$dir_dist"
mkdir "$dir_dist/policies.json"
as_root() { unprivileged_as_root "$@"; }
if browser_policy_install_firefox_policies "$dir_dist" 2>/dev/null; then
  fail "Firefox policy install refuses a planted policies.json directory"
fi
[[ -d $dir_dist/policies.json ]] || fail "Firefox policy install leaves a planted policies.json directory in place"
pass "Firefox policy install does not write into a planted policies.json directory"

grep -F 'exit "$failed"' "$ROOT/bin/omarchy-theme-set-browser" >/dev/null ||
  fail "omarchy-theme-set-browser exits non-zero when a policy write fails"
pass "omarchy-theme-set-browser exits non-zero when a policy write fails"

# Bash 5.3 adopts the EXIT trap's last status as the script's exit status, so a
# handler ending on a false test turns a clean run into a failure and aborts the
# migration that calls this through omarchy-theme-set-browser.
policy_cleanup=$(sed -n '/^cleanup() {/,/^}/p' "$ROOT/bin/omarchy-theme-set-browser-policy")
[[ -n $policy_cleanup ]] || fail "omarchy-theme-set-browser-policy defines an EXIT cleanup handler"
eval "$policy_cleanup"
staged=""
cleanup || fail "omarchy-theme-set-browser-policy's EXIT trap succeeds with nothing staged"
staged=$test_tmp/staged-policy
: >"$staged"
cleanup || fail "omarchy-theme-set-browser-policy's EXIT trap succeeds with a staged file"
[[ ! -e $staged ]] || fail "omarchy-theme-set-browser-policy's EXIT trap removes the staged file"
unset -f cleanup
pass "omarchy-theme-set-browser-policy's EXIT trap never leaks a failure status"

grep -F 'omarchy-theme-set-browser || true' "$ROOT/migrations/1787515927.sh" >/dev/null ||
  fail "the policy-directory migration hardens Firefox even when the theme refresh fails"
pass "the policy-directory migration does not abort on a failed theme refresh"

policy_files=(
  "$ROOT/bin/omarchy-install-browser"
  "$ROOT/bin/omarchy-provision-owner"
  "$ROOT/bin/omarchy-theme-set-browser"
  "$ROOT/bin/omarchy-theme-set-browser-policy"
  "$ROOT/bin/omarchy-upgrade-to-quattro"
  "$ROOT/install/config/theme-system.sh"
  "$ROOT/install/config/browser-policy.sh"
  "$ROOT/install/helpers/browser-policy.sh"
  "$ROOT/migrations/1787515927.sh"
)
if grep -nE 'chmod a\+rwx\b|chmod a\+rw\b|chmod a\+w\b|chmod o\+w|chmod ugo\+w|chmod 2775\b|chmod 2777\b|chmod 0777\b|chmod 777\b|install -d -m 0?[27]?777|omarchy-browser-policy' "${policy_files[@]}" >/dev/null; then
  fail "browser policy setup is not world-writable and does not use omarchy-browser-policy"
fi
pass "browser policy setup is not world-writable"

mapfile -t migrations < <(rg -l 'Stop world-writable Chromium and Firefox policy directories' "$ROOT/migrations")
(( ${#migrations[@]} == 1 )) || fail "exactly one migration locks existing policy directories" "${migrations[*]}"
grep -F 'browser_policy_setup_dir' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration repairs managed directories"
if grep -F 'browser_policy_grant_user' "${migrations[0]}" >/dev/null; then
  fail "the policy-directory migration does not grant a browser-policy group"
fi
grep -F 'BROWSER_POLICY_FIREFOX_DIRS' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration covers Firefox and Zen"
grep -F 'browser_policy_firefox_policy_file_ok' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration keeps a trusted Firefox policies.json"
grep -F '/opt/zen-browser/distribution' "$ROOT/install/helpers/browser-policy.sh" >/dev/null ||
  fail "the shared helper names the Zen distribution directory"
pass "a migration locks existing policy directories"
