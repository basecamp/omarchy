#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin=$test_tmp/bin
mkdir -p "$mock_bin"
elev_log=$test_tmp/elev.log
cat >"$mock_bin/sudo" <<SH
#!/bin/bash
printf 'SUDO %s\\n' "\$*" >>"$elev_log"
[[ \${OMARCHY_TEST_SUDO_FAIL:-} == 1 ]] && exit 1
exit 0
SH
cat >"$mock_bin/pkexec" <<SH
#!/bin/bash
printf 'PKEXEC %s\\n' "\$*" >>"$elev_log"
[[ \${OMARCHY_TEST_SUDO_FAIL:-} == 1 ]] && exit 1
exit 0
SH
chmod +x "$mock_bin/sudo" "$mock_bin/pkexec"
export PATH="$mock_bin:$PATH"
: >"$elev_log"
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
browser_policy_write_color "$write_dir" "#aabbcc" ||
  fail "theme colour writes into a writable policy directory"
grep -F '"BrowserThemeColor": "#aabbcc"' "$write_dir/color.json" >/dev/null ||
  fail "theme colour writes BrowserThemeColor"
mode=$(stat -c '%a' "$write_dir/color.json")
[[ $mode == "664" ]] || fail "theme colour creates a group-writable policy file" "mode=$mode"
pass "theme colour writes a group-writable color.json"

if (( EUID == 0 )); then
  pass "running as root; skipping the mktemp-failure check"
else
  chmod u+w "$write_dir"
  export TMPDIR=$test_tmp/missing-tmp
  if browser_policy_write_color "$write_dir" "#dead00" 2>/dev/null; then
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
browser_policy_write_color "$write_dir" "#aabbcc" ||
  fail "theme colour replaces a planted color.json symlink"
[[ -f $write_dir/color.json && ! -L $write_dir/color.json ]] ||
  fail "theme colour unlinks a planted color.json symlink instead of writing through it"
grep -Fxq 'original' "$test_tmp/pwn" || fail "theme colour leaves the symlink target unchanged"
pass "theme colour does not follow a planted color.json symlink"

plant_write=$test_tmp/plant-dir
mkdir -p "$plant_write/color.json/nested"
printf 'inside\n' >"$plant_write/color.json/nested/x"
browser_policy_write_color "$plant_write" "#aabbcc" ||
  fail "theme colour replaces a planted color.json directory"
[[ -f $plant_write/color.json && ! -d $plant_write/color.json ]] ||
  fail "theme colour does not write into a planted color.json directory"
pass "theme colour does not write into a planted color.json directory"

missing_dir=$test_tmp/missing
browser_policy_write_color "$missing_dir" "#aabbcc" ||
  fail "theme colour skips a policy directory that does not exist"
[[ ! -e $missing_dir ]] || fail "theme colour does not create a missing policy directory"
pass "theme colour skips a missing policy directory"

if (( EUID == 0 )); then
  pass "running as root; skipping elevation checks"
else
  denied_dir=$test_tmp/denied
  mkdir -p "$denied_dir"
  chmod a-w "$denied_dir"
  owner=${USER:-$(id -un)}
  : >"$elev_log"
  browser_policy_write_color "$denied_dir" "#aabbcc" ||
    fail "elevated install reports success from pkexec"
  grep -E "^PKEXEC install -m 664 -o $owner -g omarchy-browser-policy -T .+ $denied_dir/color.json$" "$elev_log" >/dev/null ||
    fail "without a controlling tty, colour write elevates through pkexec as the owner" "$(cat "$elev_log")"
  if grep -E '^SUDO ' "$elev_log" >/dev/null; then
    fail "without a controlling tty, colour write does not call sudo" "$(cat "$elev_log")"
  fi
  pass "without a controlling tty, colour write elevates through pkexec"

  : >"$elev_log"
  export OMARCHY_TEST_SUDO_FAIL=1
  if browser_policy_write_color "$denied_dir" "#aabbcc" 2>"$test_tmp/write.err"; then
    fail "theme colour fails when the policy directory is not writable"
  fi
  unset OMARCHY_TEST_SUDO_FAIL
  grep -F 'omarchy-browser-policy' "$test_tmp/write.err" >/dev/null ||
    fail "theme colour names the group when the write is denied"
  pass "theme colour reports a denied policy write"

  if command -v script >/dev/null; then
    : >"$elev_log"
    cat >"$test_tmp/tty-write.sh" <<EOF
source "$ROOT/install/helpers/browser-policy.sh"
browser_policy_write_color "$denied_dir" "#aabbcc"
EOF
    script -q -c "PATH='$mock_bin:$PATH' OMARCHY_PATH='$ROOT' bash '$test_tmp/tty-write.sh'" /dev/null >/dev/null
    grep -E "^SUDO install -m 664 -o $owner -g omarchy-browser-policy -T .+ $denied_dir/color.json$" "$elev_log" >/dev/null ||
      fail "with a controlling tty, colour write elevates through sudo" "$(cat "$elev_log")"
    if grep -E '^PKEXEC ' "$elev_log" >/dev/null; then
      fail "with a controlling tty, colour write does not call pkexec" "$(cat "$elev_log")"
    fi
    pass "with a controlling tty, colour write elevates through sudo"
  else
    pass "script(1) unavailable; skipping the controlling-tty elevation check"
  fi
fi

planted_dir=$test_tmp/planted
mkdir -p "$planted_dir/evil"
printf 'evil\n' >"$planted_dir/evil/f"
printf 'old\n' >"$planted_dir/color.json"
as_root() { unprivileged_as_root "$@"; }
browser_policy_setup_dir "$planted_dir"
[[ ! -e $planted_dir/evil ]] || fail "policy setup drops a non-empty non-root subdirectory"
[[ ! -e $planted_dir/color.json ]] || fail "policy setup drops a non-root color.json"
[[ -d $planted_dir ]] || fail "policy setup leaves the managed directory in place"
pass "policy setup drops non-root files and non-empty subdirectories"

owned=$test_tmp/not-root
mkdir -p "$owned"
chmod 2775 "$owned"
BROWSER_POLICY_GROUP=$(id -gn)
if browser_policy_dir_hardened "$owned"; then
  fail "a user-owned 2775 directory is not treated as hardened"
fi
BROWSER_POLICY_GROUP=omarchy-browser-policy
pass "a hardened directory must be root-owned"

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

grant_log=$test_tmp/usermod.calls
as_root() {
  if [[ $1 == "usermod" ]]; then
    printf '%s\n' "$*" >>"$grant_log"
    return 0
  fi
  unprivileged_as_root "$@"
}
invoker=${USER:-$(id -un)}
: >"$grant_log"
SUDO_USER=$invoker
browser_policy_grant_user root
unset SUDO_USER
grep -qx -- "usermod -aG omarchy-browser-policy $invoker" "$grant_log" ||
  fail "granting as root uses SUDO_USER" "$(cat "$grant_log")"
: >"$grant_log"
OMARCHY_INSTALL_USER=""
browser_policy_grant_user ""
[[ ! -s $grant_log ]] || fail "an empty grant does not usermod"
pass "sudo install browser grants the invoking user, not root"

grep -F 'exit "$failed"' "$ROOT/bin/omarchy-theme-set-browser" >/dev/null ||
  fail "omarchy-theme-set-browser exits non-zero when a policy write fails"
pass "omarchy-theme-set-browser exits non-zero when a policy write fails"

policy_files=(
  "$ROOT/bin/omarchy-install-browser"
  "$ROOT/bin/omarchy-provision-owner"
  "$ROOT/bin/omarchy-theme-set-browser"
  "$ROOT/bin/omarchy-upgrade-to-quattro"
  "$ROOT/install/config/theme-system.sh"
  "$ROOT/install/config/browser-policy.sh"
  "$ROOT/install/helpers/browser-policy.sh"
  "$ROOT/migrations/1787515927.sh"
)
if grep -nE 'chmod a\+rwx\b|chmod a\+rw\b|chmod a\+w\b|chmod o\+w|chmod ugo\+w|chmod 2777\b|chmod 0777\b|chmod 777\b|install -d -m 0?[27]?777' "${policy_files[@]}" >/dev/null; then
  fail "browser policy setup is not world-writable"
fi
pass "browser policy setup is not world-writable"

mapfile -t migrations < <(rg -l 'Stop world-writable Chromium and Firefox policy directories' "$ROOT/migrations")
(( ${#migrations[@]} == 1 )) || fail "exactly one migration locks existing policy directories" "${migrations[*]}"
grep -F 'browser_policy_dir_hardened' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration no-ops a machine already repaired"
grep -F 'browser_policy_grant_user' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration still grants the current user the group"
grep -F 'BROWSER_POLICY_FIREFOX_DIRS' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration covers Firefox and Zen"
grep -F 'browser_policy_firefox_policy_file_ok' "${migrations[0]}" >/dev/null ||
  fail "the policy-directory migration keeps a trusted Firefox policies.json"
grep -F '/opt/zen-browser/distribution' "$ROOT/install/helpers/browser-policy.sh" >/dev/null ||
  fail "the shared helper names the Zen distribution directory"
pass "a migration locks existing policy directories"
