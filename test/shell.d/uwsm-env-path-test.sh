#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub_bin="$tmpdir/stub-bin"
mkdir -p "$home" "$stub_bin"

# `mise activate --shims` prepends the shims directory. Stub it so the test does
# not depend on mise being installed, and so a fallback activation is visible in
# the resulting PATH.
cat >"$stub_bin/mise" <<'STUB'
#!/bin/bash
printf 'export PATH="$HOME/.local/share/mise/shims:$PATH"\n'
STUB
cat >"$stub_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB
chmod +x "$stub_bin/mise" "$stub_bin/omarchy-cmd-present"

# Test against copies so the test controls the bootstrap it loads without
# depending on an installed Omarchy.
bootstrap="$tmpdir/env-bootstrap"
sed "s#/etc/omarchy.conf#$tmpdir/omarchy.conf#g" "$ROOT/default/bash/env-bootstrap" >"$bootstrap"
printf 'export OMARCHY_PATH="/usr/share/omarchy"\n' >"$tmpdir/omarchy.conf"

env_d="$tmpdir/10-omarchy"
sed "s#/usr/share/omarchy/default/bash/env-bootstrap#$bootstrap#g" "$ROOT/default/uwsm/env.d/10-omarchy" >"$env_d"

# A variant whose bootstrap is missing, to exercise the fallback activation.
env_d_no_bootstrap="$tmpdir/10-omarchy-no-bootstrap"
sed "s#/usr/share/omarchy/default/bash/env-bootstrap#$tmpdir/absent-bootstrap#g" "$ROOT/default/uwsm/env.d/10-omarchy" >"$env_d_no_bootstrap"

run_env_d() {
  local script="$1"
  local path_value="$2"

  HOME="$home" PATH="$path_value" sh -c '. "$1"; printf "%s\n" "$PATH"' sh "$script"
}

count_path_entry() {
  local path_value="$1"
  local entry="$2"

  printf '%s' "$path_value" | tr ':' '\n' | grep -cxF "$entry" || true
}

path_index() {
  local path_value="$1"
  local entry="$2"

  printf '%s' "$path_value" | tr ':' '\n' | grep -nxF "$entry" | head -1 | cut -d: -f1
}

shims="$home/.local/share/mise/shims"

result=$(run_env_d "$env_d" "$stub_bin:/usr/bin")

count=$(count_path_entry "$result" "$shims")
(( count == 1 )) || fail "uwsm env.d adds the mise shims exactly once" "expected 1 occurrence, found $count\nactual PATH: $result"
pass "uwsm env.d adds the mise shims exactly once"

shims_index=$(path_index "$result" "$shims")
usr_bin_index=$(path_index "$result" "/usr/bin")
[[ -n $shims_index && -n $usr_bin_index ]] || fail "uwsm env.d keeps /usr/bin and the shims on PATH" "actual PATH: $result"
(( usr_bin_index < shims_index )) || fail "uwsm env.d keeps system binaries ahead of the mise shims" "/usr/bin at #$usr_bin_index, shims at #$shims_index\nactual PATH: $result"
pass "uwsm env.d keeps system binaries ahead of the mise shims"

# Without the bootstrap the shims are not on PATH yet, so mise still activates.
fallback=$(run_env_d "$env_d_no_bootstrap" "$stub_bin:/usr/bin")
fallback_count=$(count_path_entry "$fallback" "$shims")
(( fallback_count == 1 )) || fail "uwsm env.d activates mise when the bootstrap did not run" "expected 1 occurrence, found $fallback_count\nactual PATH: $fallback"
pass "uwsm env.d activates mise when the bootstrap did not run"
