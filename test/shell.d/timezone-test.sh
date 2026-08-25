#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

timezone_menu="$ROOT/bin/omarchy-menu-timezone"
polkit_rule="$ROOT/default/polkit-1/rules.d/49-omarchy-timezone.rules"

# The timezone is set through systemd-timedated, which is already privileged,
# bus-activated and confined to CAP_SYS_TIME. The value crosses as a typed D-Bus
# string, so no argument string exists for a second option to hide in.
grep -F 'busctl -- call org.freedesktop.timedate1 /org/freedesktop/timedate1' "$timezone_menu" >/dev/null ||
  fail "timezone menu sets the timezone over the bus"

grep -F 'org.freedesktop.timedate1 SetTimezone sb "$timezone" true' "$timezone_menu" >/dev/null ||
  fail "timezone menu calls SetTimezone with the timezone and interactive authentication"

# Escalating a general-purpose binary is the shape this replaced. sudoers matches
# arguments as one concatenated string, so any grant on timedatectl has to keep
# a second argument (-H makes it spawn ssh) from riding along behind the
# timezone. Naming the action instead leaves nothing to narrow. Comments are
# stripped first so the ones explaining that history do not count as uses.
! grep -vE '^[[:space:]]*#' "$timezone_menu" | grep -qE '\bsudo\b|\bpkexec\b' ||
  fail "timezone menu does not escalate a binary to set the timezone"

[[ ! -e $ROOT/etc/sudoers.d/omarchy-tzupdate ]] ||
  fail "timezone no longer ships a passwordless sudoers rule for timedatectl"

! grep -rIF 'omarchy-tzupdate' "$ROOT/etc" >/dev/null 2>&1 ||
  fail "no sudoers drop-in still references the retired tzupdate grant"

[[ -f $polkit_rule ]] ||
  fail "timezone ships a polkit rule granting the timedated action"

grep -F 'omarchy-shell -q omarchy.clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu refreshes the namespaced clock IPC target"

! grep -F 'omarchy-shell -q Clock refresh' "$timezone_menu" >/dev/null ||
  fail "timezone menu no longer refreshes the retired Clock IPC target"

pass "timezone menu sets the timezone over D-Bus and refreshes the clock"

# The menu has no terminal to carry a password prompt, so the polkit rule is what
# keeps it from stopping for one. Run the rule the way polkitd does -- stub the
# polkit global, evaluate the file, then ask the registered callback to decide --
# so the gate is tested by its answers rather than by its text.
run_node_test <<'JS'
const fs = require('fs')

const source = fs.readFileSync(
  path.join(root, 'default/polkit-1/rules.d/49-omarchy-timezone.rules'),
  'utf8'
)

const rules = []
const polkit = {
  Result: {
    YES: 'YES',
    NO: 'NO',
    AUTH_SELF: 'AUTH_SELF',
    AUTH_ADMIN: 'AUTH_ADMIN',
    NOT_HANDLED: 'NOT_HANDLED',
  },
  addRule(rule) {
    rules.push(rule)
  },
}

new Function('polkit', source)(polkit)

assertEqual(rules.length, 1, 'timezone polkit rule registers exactly one rule')

const TIMEZONE_ACTION = 'org.freedesktop.timedate1.set-timezone'

// A rule that returns nothing leaves the action to the rules after it, and
// finally to the action's own default, which is to authenticate.
function decide(actionId, options) {
  const { groups = ['wheel'], local = true, active = true } = options || {}

  return rules[0](
    { id: actionId },
    {
      isInGroup: (group) => groups.includes(group),
      local,
      active,
    }
  )
}

assertEqual(
  decide(TIMEZONE_ACTION),
  'YES',
  'a local active wheel session sets the timezone without a password'
)

assertEqual(
  decide(TIMEZONE_ACTION, { local: false }),
  undefined,
  'a remote session still has to authenticate'
)

assertEqual(
  decide(TIMEZONE_ACTION, { active: false }),
  undefined,
  'an inactive session still has to authenticate'
)

assertEqual(
  decide(TIMEZONE_ACTION, { groups: [] }),
  undefined,
  'a session outside wheel still has to authenticate'
)

assertEqual(
  decide('org.freedesktop.timedate1.set-time'),
  undefined,
  'the grant does not reach set-time on the same interface'
)

assertEqual(
  decide('org.freedesktop.timedate1.set-ntp'),
  undefined,
  'the grant does not reach set-ntp on the same interface'
)

assertEqual(
  decide('org.freedesktop.systemd1.manage-units'),
  undefined,
  'the grant does not reach actions on other services'
)
JS
