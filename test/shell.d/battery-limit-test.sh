#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setter="$ROOT/bin/omarchy-battery-limit-set"
getter="$ROOT/bin/omarchy-battery-limit-get"
hw="$ROOT/bin/omarchy-hw-battery-charge-limit"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-battery-limit"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-battery-limit-set 80, /usr/bin/omarchy-battery-limit-set 90, /usr/bin/omarchy-battery-limit-set 100'

# Exactly one rule, matched whole. A second line -- or the same command with
# its argument dropped, which sudoers reads as "any arguments" -- would widen
# the grant while leaving this line in place.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "battery-limit sudoers file carries exactly the three-preset rule and nothing else" "got: $rules"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "battery-limit sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-battery-limit-set' "$setter" >/dev/null ||
  fail "omarchy-battery-limit-set elevates the path the sudoers rule names"

# `sudo -l` on its own answers whether a command is permitted, not whether it
# is passwordless, and Omarchy ships a blanket %wheel rule that permits
# everything. Only the long listing prints the matched entry's tags.
grep -E 'sudo -n -l -l' "$setter" >/dev/null ||
  fail "omarchy-battery-limit-set reads the grant from the long sudo listing"

pass "battery-limit sudoers rule is scoped to the three presets"

# The privileged half runs as root under sudo's secure_path, and a dev link
# (etc/sudoers.d/omarchy-dev-path) prepends a user-writable checkout bin/ to
# it. Every helper the script calls by bare name is a system tool, so once it
# holds root the script pins PATH to trusted system directories and never
# resolves one of them out of the checkout.
grep -Eq '^\s*export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin' "$setter" ||
  fail "omarchy-battery-limit-set pins PATH to trusted system directories when it holds root"
# require_root carries its own `(( EUID == 0 ))`, so matching that text alone
# would pass with the pin deleted. Anchor on the unindented guard and require
# the pin to be the line it opens.
gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$setter" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "omarchy-battery-limit-set gates the trusted-PATH pin on holding root"

pass "omarchy-battery-limit-set pins PATH to trusted system directories when root"

# Argument validation runs before require_root, so a rejected value never
# reaches sudo/pkexec -- and these checks never need root.
check_reject() {
  local description="$1"
  shift
  local output status

  if output=$("$setter" "$@" </dev/null 2>&1); then
    status=0
  else
    status=$?
  fi

  (( status == 2 )) || fail "$description exits 2" "got exit $status: $output"
  [[ $output == "Usage: omarchy-battery-limit-set"* ]] ||
    fail "$description prints usage to stderr" "got: $output"
}

check_reject "no argument"
check_reject "unsupported preset" 50
check_reject "non-numeric argument" full
check_reject "extra arguments" 80 90

pass "omarchy-battery-limit-set rejects anything but 80, 90, 100 with exit 2"

# require_root returns immediately for root, so the stubs below would not
# stand between the script and this machine's real sysfs and /etc.
if (( EUID == 0 )); then
  pass "running as root; skipping the elevation checks, which would write to sysfs"
else
  test_tmp=$(mktemp -d)
  trap 'rm -rf "$test_tmp"' EXIT

  stub_bin="$test_tmp/bin"
  mkdir -p "$stub_bin"

  # pkexec stands in for the exec at the end of require_root, so the sysfs
  # writes below it never run and real pkexec is never reached.
  cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH
  chmod +x "$stub_bin/pkexec"

  # The sudo stub plays both parts: it answers the passwordless probe from
  # STUB_GRANTED, the presets etc/sudoers.d/omarchy-battery-limit covers on
  # this machine, and logs the elevation otherwise. STUB_GRANTED empty stands
  # for an install whose omarchy-settings predates the file.
  cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l ]]; then
  for granted in ${STUB_GRANTED-80 90 100}; do
    [[ ${!#} == "$granted" ]] || continue
    echo "    Options: !authenticate"
    exit 0
  done
  echo "    Matched: ${!#}"
  exit 0
fi
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH
  chmod +x "$stub_bin/sudo"

  elevation_for() {
    : >"$test_tmp/elevation"
    ELEVATION_LOG="$test_tmp/elevation" \
    PATH="$stub_bin:$PATH" \
      bash "$setter" "$1" </dev/null >/dev/null
    cat "$test_tmp/elevation"
  }

  for preset in 80 90 100; do
    elevation=$(elevation_for "$preset")
    [[ $elevation == "sudo /usr/bin/omarchy-battery-limit-set $preset" ]] ||
      fail "omarchy-battery-limit-set takes the passwordless sudo grant for $preset without a terminal" "got: $elevation"
  done

  pass "omarchy-battery-limit-set elevates the presets through sudo, not polkit"

  # A dev-linked checkout elevates the packaged path like everyone else,
  # rather than handing sudo a path no rule can name and losing the grant.
  dev_linked=$(OMARCHY_PATH="$test_tmp/checkout" elevation_for 80)
  [[ $dev_linked == "sudo /usr/bin/omarchy-battery-limit-set 80" ]] ||
    fail "omarchy-battery-limit-set elevates the system install wherever OMARCHY_PATH points" "got: $dev_linked"

  # The grant is what makes sudo passwordless, so its absence -- an install
  # still on an older omarchy-settings, or a user outside %wheel the rule
  # cannot match -- has to route to polkit.
  ungranted=$(STUB_GRANTED="" elevation_for 80)
  [[ $ungranted == "pkexec /usr/bin/omarchy-battery-limit-set 80" ]] ||
    fail "omarchy-battery-limit-set falls back to polkit where the sudoers grant is not installed" "got: $ungranted"

  pass "omarchy-battery-limit-set falls back to polkit wherever the grant does not reach"

  rm -rf "$test_tmp"
  trap - EXIT
fi

# The hw gate and the getter read sysfs through OMARCHY_POWER_SUPPLY_PATH, so
# point them at a fixture instead of depending on this machine's battery.
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/BAT0"

if OMARCHY_POWER_SUPPLY_PATH="$fixture" "$hw"; then
  fail "hw battery-charge-limit exits 1 when no battery exposes the threshold file"
fi
pass "hw battery-charge-limit exits 1 without a charge_control_end_threshold"

if output=$(OMARCHY_POWER_SUPPLY_PATH="$fixture" "$getter" 2>&1); then
  fail "battery-limit-get exits 1 when no battery exposes the threshold file"
fi
[[ -z $output ]] ||
  fail "battery-limit-get stays silent when it finds nothing" "got: $output"
pass "battery-limit-get exits 1 silently without a charge_control_end_threshold"

printf '80\n' >"$fixture/BAT0/charge_control_end_threshold"

OMARCHY_POWER_SUPPLY_PATH="$fixture" "$hw" ||
  fail "hw battery-charge-limit exits 0 when a battery exposes the threshold file"
pass "hw battery-charge-limit exits 0 with a readable charge_control_end_threshold"

value=$(OMARCHY_POWER_SUPPLY_PATH="$fixture" "$getter")
[[ $value == "80" ]] ||
  fail "battery-limit-get prints the threshold of the first battery" "got: $value"
pass "battery-limit-get prints the current charge limit"

mkdir -p "$fixture/BAT1"
printf '90\n' >"$fixture/BAT1/charge_control_end_threshold"

value=$(OMARCHY_POWER_SUPPLY_PATH="$fixture" "$getter")
[[ $value == "80" || $value == "90" ]] ||
  fail "battery-limit-get prints one battery's threshold when several exist" "got: $value"
pass "battery-limit-get reads the first battery when several exist"
