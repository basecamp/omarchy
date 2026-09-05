#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

timezone_menu="$ROOT/bin/omarchy-menu-timezone"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-tzupdate"

grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/timedatectl ^set-timezone [A-Za-z0-9_+][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+][A-Za-z0-9_+.-]*)*$' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule allows passwordless timedatectl timezone changes"

! grep -F 'set-timezone *' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule uses a bare wildcard that admits extra arguments like -H and -M"

! grep -F 'tzupdate' "$sudoers_file" >/dev/null ||
  fail "timezone sudoers rule does not grant passwordless tzupdate"

grep -F 'sudo timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu uses the passwordless sudoers timedatectl rule"

! grep -F 'pkexec timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not wrap timedatectl in pkexec"

! grep -F 'pkexec /usr/bin/timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not wrap timedatectl in pkexec"

! grep -F 'sudo /usr/bin/timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu lets sudo resolve timedatectl from its secure path"

! grep -Fx 'timedatectl set-timezone "$timezone"' "$timezone_menu" >/dev/null ||
  fail "timezone menu does not use bare timedatectl, which triggers polkit, as its main path"

grep -F 'omarchy-shell -q omarchy.clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu refreshes the namespaced clock IPC target"

! grep -F 'omarchy-shell -q Clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu no longer refreshes the retired Clock IPC target"

pass "timezone menu refreshes clock after timezone changes"

# The grant is what makes the sudo path silent. Where it does not reach -- the
# kid account on a child install, or an older omarchy-settings -- the menu has
# no terminal for sudo to ask on, so it must fall through to timedated's own
# polkit prompt rather than fail without a word.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-menu-select" <<'SH'
#!/bin/bash
cat >/dev/null
echo "Europe/Copenhagen"
SH

# The sudo stub answers the passwordless probe from STUB_GRANTED and logs any
# elevation; timedatectl logs the bare call the fallback makes.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l ]]; then
  if [[ ${STUB_GRANTED:-} == 1 ]]; then
    echo "    Options: !authenticate"
  else
    echo "    Matched: ${!#}"
  fi
  exit 0
fi
printf 'sudo %s\n' "$*" >>"$ELEVATION_LOG"
SH

cat >"$stub_bin/timedatectl" <<'SH'
#!/bin/bash
if [[ $1 == list-timezones ]]; then
  printf '%s\n' UTC Europe/Copenhagen
  exit 0
fi
printf 'timedatectl %s\n' "$*" >>"$ELEVATION_LOG"
SH

for helper in omarchy-shell omarchy-notification-send; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$helper"
done
chmod +x "$stub_bin"/*

elevation_for() {
  : >"$test_tmp/elevation"
  STUB_GRANTED="$1" ELEVATION_LOG="$test_tmp/elevation" PATH="$stub_bin:$PATH" \
    bash "$timezone_menu" </dev/null >/dev/null
  cat "$test_tmp/elevation"
}

granted=$(elevation_for 1)
[[ $granted == 'sudo timedatectl set-timezone Europe/Copenhagen' ]] ||
  fail "timezone menu takes the passwordless sudo grant without a terminal" "got: $granted"

ungranted=$(elevation_for 0)
[[ $ungranted == 'timedatectl set-timezone Europe/Copenhagen' ]] ||
  fail "timezone menu falls through to timedated's polkit prompt where the grant does not reach" "got: $ungranted"

pass "timezone menu prompts through polkit where the passwordless grant does not reach"
