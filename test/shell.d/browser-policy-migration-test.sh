#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787676640.sh"

[[ -f $migration ]] || fail "browser policy repair migration exists"
[[ $(stat -c '%a' "$migration") == 644 ]] || fail "browser policy repair migration is not executable"
grep -Fxq '    omarchy-theme-set-browser' "$migration" ||
  fail "browser policy migration reuses the constrained Chromium policy writer"
grep -Fq '/usr/lib/firefox/distribution /opt/zen-browser/distribution' "$migration" ||
  fail "browser policy migration covers Firefox and Zen distribution directories"
grep -Fq 'not a root-owned Omarchy tree' "$migration" ||
  fail "browser policy migration refuses to install policy out of a non-root-owned tree"
grep -Fq 'chromium_has_refused_policy_path' "$migration" ||
  fail "browser policy migration detects refused Chromium paths by inspection"
grep -Fq 'needs admin attention' "$migration" ||
  fail "browser policy migration warns on refused paths instead of swallowing failures"
grep -Fxq '    omarchy-theme-set-browser' "$migration" ||
  fail "browser policy migration propagates Chromium theme write failures"

pass "browser policy migration covers existing supported browser installs"

if ! command -v bwrap >/dev/null ||
  ! bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / \
    --overlay-src /etc --tmp-overlay /etc \
    --overlay-src /usr/lib --tmp-overlay /usr/lib \
    --overlay-src /opt --tmp-overlay /opt true 2>/dev/null; then
  pass "Bubblewrap user namespaces unavailable; skipping browser policy migration runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
theme_home="$test_tmp/home"
theme_dir="$theme_home/.local/state/omarchy/current/theme"
theme_calls="$test_tmp/theme-calls"
sudo_calls="$test_tmp/sudo-calls"
mkdir -p "$stub_bin" "$theme_dir"
printf '10,20,30\n' >"$theme_dir/chromium.theme"

cat >"$stub_bin/omarchy-theme-set-browser" <<'SH'
#!/bin/bash
printf 'theme\n' >>"$THEME_CALLS"
exec "$OMARCHY_PATH/bin/omarchy-theme-set-browser"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"
exec "$@"
SH

ln -s "$ROOT/bin/omarchy-theme-browser-policy" "$stub_bin/omarchy-theme-browser-policy"
chmod +x "$stub_bin/omarchy-theme-set-browser" "$stub_bin/omarchy-cmd-present" "$stub_bin/sudo"

seed_hostile_entries() {
  local policy_dir=$1

  printf '{"Unsafe": true}\n' >"$policy_dir/unsafe.json"
  chmod 0666 "$policy_dir/unsafe.json"
  printf 'hidden\n' >"$policy_dir/.omarchy-hidden"
  chmod 0666 "$policy_dir/.omarchy-hidden"
  printf 'spaced\n' >"$policy_dir/with space.json"
  chmod 0666 "$policy_dir/with space.json"
  printf 'dashed\n' >"$policy_dir/-dash-led.json"
  chmod 0666 "$policy_dir/-dash-led.json"
  printf '{"Safe": true}\n' >"$policy_dir/admin.json"
  chmod 0644 "$policy_dir/admin.json"
  printf '{"Setuid": true}\n' >"$policy_dir/setuid-admin.json"
  chmod 4755 "$policy_dir/setuid-admin.json"
  mkdir "$policy_dir/sticky-dir"
  chmod 1777 "$policy_dir/sticky-dir"
  mkfifo "$policy_dir/fifo-pipe"
}

chromium_dirs=(chromium chrome edge brave)
for browser in "${chromium_dirs[@]}"; do
  policy_dir="$test_tmp/$browser/managed"
  mkdir -p "$policy_dir/nested"
  chmod 0777 "$policy_dir"
  printf 'nested\n' >"$policy_dir/nested/policy.json"
  ln -s "$test_tmp/outside" "$policy_dir/color.json"
  seed_hostile_entries "$policy_dir"
done

firefox_dir="$test_tmp/firefox/distribution"
zen_dir="$test_tmp/zen/distribution"
mkdir -p "$firefox_dir/admin-assets" "$zen_dir"
chmod 0777 "$firefox_dir" "$zen_dir"
printf 'keep\n' >"$firefox_dir/admin-assets/keep.txt"
printf '{"Admin": true}\n' >"$firefox_dir/admin.json"
chmod 0644 "$firefox_dir/admin.json"
printf '{"policies":{"DisableSecurity":true}}\n' >"$firefox_dir/policies.json"
chmod 0666 "$firefox_dir/policies.json"
printf 'unsafe\n' >"$firefox_dir/unsafe-file"
chmod 0666 "$firefox_dir/unsafe-file"
ln -s "$test_tmp/outside" "$firefox_dir/unsafe-link"

common_sandbox_args=(
  --unshare-user
  --uid 0
  --gid 0
  --ro-bind / /
  --bind "$test_tmp" "$test_tmp"
  --proc /proc
  --dev /dev
  --overlay-src /etc
  --tmp-overlay /etc
  --overlay-src /usr/lib
  --tmp-overlay /usr/lib
  --overlay-src /opt
  --tmp-overlay /opt
)

sandbox_args=(
  "${common_sandbox_args[@]}"
  --dir /etc/chromium
  --dir /etc/chromium/policies
  --bind "$test_tmp/chromium/managed" /etc/chromium/policies/managed
  --dir /etc/opt
  --dir /etc/opt/chrome
  --dir /etc/opt/chrome/policies
  --bind "$test_tmp/chrome/managed" /etc/opt/chrome/policies/managed
  --dir /etc/opt/edge
  --dir /etc/opt/edge/policies
  --bind "$test_tmp/edge/managed" /etc/opt/edge/policies/managed
  --dir /etc/brave
  --dir /etc/brave/policies
  --bind "$test_tmp/brave/managed" /etc/brave/policies/managed
  --dir /usr/lib/firefox
  --bind "$firefox_dir" /usr/lib/firefox/distribution
  --dir /opt/zen-browser
  --bind "$zen_dir" /opt/zen-browser/distribution
)

run_migration() {
  local err_log=${1:-/dev/null}

  HOME="$theme_home" \
  OMARCHY_PATH="$ROOT" \
  PATH="$stub_bin:/usr/bin:/bin" \
  THEME_CALLS="$theme_calls" \
  SUDO_CALLS="$sudo_calls" \
    bwrap "${sandbox_args[@]}" bash -euo pipefail "$migration" >/dev/null 2>"$err_log"
}

: >"$theme_calls"
: >"$sudo_calls"
run_migration

[[ $(wc -l <"$theme_calls") == 1 ]] ||
  fail "browser policy migration invokes the Chromium repair once" "got: $(<"$theme_calls")"

for browser in "${chromium_dirs[@]}"; do
  policy_dir="$test_tmp/$browser/managed"
  [[ $(stat -c '%a' "$policy_dir") == 755 ]] || fail "$browser policy directory is secured"
  [[ -f $policy_dir/admin.json ]] || fail "$browser safe administrator policy is preserved"
  [[ $(stat -c '%a' "$policy_dir/setuid-admin.json") == 4755 ]] ||
    fail "$browser root-owned special-bit policy is preserved"
  for hostile in unsafe.json .omarchy-hidden "with space.json" -dash-led.json sticky-dir; do
    [[ ! -e $policy_dir/$hostile ]] || fail "$browser hostile entry $hostile is removed"
  done
  [[ ! -p $policy_dir/fifo-pipe ]] || fail "$browser FIFO entry is removed"
  [[ ! -e $policy_dir/nested ]] || fail "$browser non-policy directory is removed"
  [[ ! -L $policy_dir/color.json ]] || fail "$browser planted color policy symlink is removed"
  [[ $(stat -c '%a' "$policy_dir/color.json") == 644 ]] || fail "$browser color policy mode is secured"
  grep -Fxq '{"BrowserThemeColor": "#0a141e", "BrowserColorScheme": "device"}' "$policy_dir/color.json" ||
    fail "$browser color policy is regenerated from the current theme"
done

[[ $(stat -c '%a' "$firefox_dir") == 755 ]] || fail "Firefox distribution directory is secured"
[[ $(stat -c '%a' "$zen_dir") == 755 ]] || fail "Zen distribution directory is secured"
[[ -f $firefox_dir/admin.json && -f $firefox_dir/admin-assets/keep.txt ]] ||
  fail "Firefox safe administrator entries are preserved"
for hostile in unsafe-file unsafe-link "with space.json" .omarchy-hidden -dash-led.json; do
  [[ ! -e $firefox_dir/$hostile ]] || fail "Firefox hostile entry $hostile is removed"
done
cmp -s "$ROOT/default/firefox/policies.json" "$firefox_dir/policies.json" ||
  fail "Firefox unsafe policy is replaced with the packaged policy"
cmp -s "$ROOT/default/firefox/policies.json" "$zen_dir/policies.json" ||
  fail "Zen missing policy is restored from the packaged policy"
[[ $(stat -c '%a' "$firefox_dir/policies.json") == 644 ]] || fail "Firefox policy mode is secured"
[[ $(stat -c '%a' "$zen_dir/policies.json") == 644 ]] || fail "Zen policy mode is secured"

pass "browser policy migration repairs unsafe existing browser state in a sandbox"

: >"$theme_calls"
: >"$sudo_calls"
run_migration

[[ ! -s $theme_calls ]] || fail "browser policy migration repeats the Chromium repair on secure state"
[[ ! -s $sudo_calls ]] || fail "browser policy migration repeats privileged distribution repairs on secure state"

pass "browser policy migration is machine-idempotent"

# One refused path must not stop the remaining repairs or wedge the migration:
# a symlinked distribution directory is refused while the other browser is
# repaired, and the run still succeeds.
firefox_b="$test_tmp/firefox-b/distribution"
zen_b="$test_tmp/zen-b"
mkdir -p "$firefox_b"
chmod 0755 "$firefox_b"
printf 'unsafe\n' >"$firefox_b/unsafe-file"
chmod 0666 "$firefox_b/unsafe-file"
printf '{"Custom": true}\n' >"$firefox_b/policies.json"
chmod 0644 "$firefox_b/policies.json"
mkdir "$zen_b"
ln -s "$test_tmp/nowhere" "$zen_b/distribution"

sandbox_args=(
  "${common_sandbox_args[@]}"
  --dir /etc/chromium
  --dir /etc/chromium/policies
  --bind "$test_tmp/chromium/managed" /etc/chromium/policies/managed
  --dir /etc/opt
  --dir /etc/opt/chrome
  --dir /etc/opt/chrome/policies
  --bind "$test_tmp/chrome/managed" /etc/opt/chrome/policies/managed
  --dir /etc/opt/edge
  --dir /etc/opt/edge/policies
  --bind "$test_tmp/edge/managed" /etc/opt/edge/policies/managed
  --dir /etc/brave
  --dir /etc/brave/policies
  --bind "$test_tmp/brave/managed" /etc/brave/policies/managed
  --dir /usr/lib/firefox
  --bind "$firefox_b" /usr/lib/firefox/distribution
  --bind "$zen_b" /opt/zen-browser
)

refusal_log="$test_tmp/refusal-log"
: >"$theme_calls"
: >"$sudo_calls"
run_migration "$refusal_log"

[[ ! -s $theme_calls ]] || fail "secure Chromium state skips the theme write in the tolerated run"
[[ ! -e $firefox_b/unsafe-file ]] || fail "the tolerated run still repairs the reachable browser"
cmp -s <(printf '{"Custom": true}\n') "$firefox_b/policies.json" ||
  fail "the tolerated run keeps a safe administrator policy"
grep -Fq 'Browser policy repair skipped: /opt/zen-browser/distribution needs admin attention' "$refusal_log" ||
  fail "the refused distribution path is reported" "got: $(<"$refusal_log")"

pass "browser policy migration tolerates one refused path while repairing the rest"

# Operational failures must propagate: the runner leaves the migration pending
# so it retries, instead of marking a half-repaired machine complete.

# A failing theme write (a canceled sudo prompt, say) aborts the whole run.
chromium_c="$test_tmp/chromium-c/managed"
mkdir -p "$chromium_c"
chmod 0777 "$chromium_c"
printf '{"Evil": true}\n' >"$chromium_c/unsafe.json"
chmod 0666 "$chromium_c/unsafe.json"

cat >"$stub_bin/omarchy-theme-set-browser" <<'SH'
#!/bin/bash
printf 'theme\n' >>"$THEME_CALLS"
exit 77
SH

sandbox_args=(
  "${common_sandbox_args[@]}"
  --dir /etc/chromium
  --dir /etc/chromium/policies
  --bind "$chromium_c" /etc/chromium/policies/managed
)

failure_log="$test_tmp/failure-log"
: >"$theme_calls"
: >"$sudo_calls"
set +e
run_migration "$failure_log"
theme_status=$?
set -e
(( theme_status == 77 )) ||
  fail "an operational Chromium theme failure propagates its exit status" "got: $theme_status"
[[ $(wc -l <"$theme_calls") == 1 ]] || fail "the failing theme write is attempted once"
[[ ! -s $sudo_calls ]] || fail "no privileged work happens after a refused theme write"

pass "browser policy migration stays pending when the Chromium repair fails operationally"

# A failing privileged step in a distribution repair aborts the run too.
# The unused Chromium paths get clean binds so host /etc state (whose
# ownership is unmapped inside the namespace) cannot look dirty and drag the
# failing theme stub into the run.
chromium_unused=(chromium-clean chrome-clean edge-clean brave-clean)
for browser in "${chromium_unused[@]}"; do
  mkdir -p "$test_tmp/$browser"
  chmod 0755 "$test_tmp/$browser"
done

firefox_c="$test_tmp/firefox-c/distribution"
mkdir -p "$firefox_c"
chmod 0777 "$firefox_c"
printf '{"policies":{"DisableSecurity":true}}\n' >"$firefox_c/policies.json"
chmod 0666 "$firefox_c/policies.json"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"
if [[ $1 == install ]]; then
  exit 9
fi
exec "$@"
SH

sandbox_args=(
  "${common_sandbox_args[@]}"
  --dir /etc/chromium
  --dir /etc/chromium/policies
  --bind "$test_tmp/chromium-clean" /etc/chromium/policies/managed
  --dir /etc/opt
  --bind "$test_tmp/chrome-clean" /etc/opt/chrome/policies/managed
  --bind "$test_tmp/edge-clean" /etc/opt/edge/policies/managed
  --dir /etc/brave
  --bind "$test_tmp/brave-clean" /etc/brave/policies/managed
  --dir /usr/lib/firefox
  --bind "$firefox_c" /usr/lib/firefox/distribution
)

distribution_log="$test_tmp/distribution-log"
: >"$sudo_calls"
set +e
run_migration "$distribution_log"
distribution_status=$?
set -e
(( distribution_status == 9 )) ||
  fail "an operational distribution repair failure propagates its exit status" "got: $distribution_status"
[[ -f $firefox_c/policies.json ]] ||
  fail "a failed distribution repair changes nothing before it aborts"

pass "browser policy migration stays pending when a distribution repair fails operationally"
