#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

packages="$ROOT/install/omarchy-base.packages"
cups_browsed_conf="$ROOT/etc/cups/cups-browsed.conf"
sysusers_conf="$ROOT/etc/sysusers.d/omarchy-cups-browsed.conf"
service_dropin="$ROOT/etc/systemd/system/cups-browsed.service.d/10-omarchy.conf"

grep -qxF cups-browsed "$packages" || fail "cups-browsed remains in the base package set"
grep -qxF cups-pk-helper "$packages" || fail "Polkit printer administration is installed"
! grep -qxF cups-pdf "$packages" || fail "the root CUPS-PDF backend is removed"

pass "the base install keeps discovery and replaces CUPS-PDF with Polkit administration"

grep -qxF 'CacheDir /var/cache/cups-browsed' "$cups_browsed_conf" ||
  fail "cups-browsed keeps state outside the print-filter cache"
grep -qxF 'CreateIPPPrinterQueues Driverless' "$cups_browsed_conf" ||
  fail "automatic queues are limited to driverless IPP printers"
grep -qxF 'CreateRemoteCUPSPrinterQueues No' "$cups_browsed_conf" ||
  fail "remote CUPS queues are not created automatically"
! grep -q 'CreateRemotePrinters' "$cups_browsed_conf" ||
  fail "the unsupported CreateRemotePrinters directive is gone"

pass "cups-browsed uses explicit supported discovery policy and an isolated cache"

grep -qxF 'u cups-browsed - "CUPS printer discovery" / -' "$sysusers_conf" ||
  fail "a locked cups-browsed system account is declared"

for setting in \
  'User=cups-browsed' \
  'Group=cups-browsed' \
  'CacheDirectory=cups-browsed' \
  'CacheDirectoryMode=0750' \
  'UMask=0027' \
  'NoNewPrivileges=yes' \
  'ProtectSystem=strict' \
  'ProtectHome=yes' \
  'PrivateTmp=yes' \
  'RestrictSUIDSGID=yes'; do
  grep -qxF "$setting" "$service_dropin" ||
    fail "cups-browsed service hardening includes $setting"
done

! grep -q '^\(Ambient\|CapabilityBoundingSet\).*CAP_NET_BIND_SERVICE' "$service_dropin" ||
  fail "cups-browsed is not granted an unverified network capability"

pass "cups-browsed runs as its confined service account without added capabilities"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/etc/cups" "$test_tmp/var/lib/omarchy/migrations"

cat >"$mock_bin/systemd-sysusers" <<'SH'
#!/bin/bash
printf 'sysusers\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
SH
cat >"$mock_bin/chown" <<'SH'
#!/bin/bash
printf 'chown\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
SH
cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == "cups" || $1 == "cups-browsed" ]]
SH
for command in omarchy-pkg-add omarchy-pkg-drop; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s\t%s\n' "${0##*/}" "$*" >>"$OMARCHY_CUPS_TEST_LOG"
SH
done
cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
exit 0
SH
cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
exec "$@"
SH
chmod +x "$mock_bin"/*

authorization_conf="$test_tmp/etc/cups/cups-files.conf"
cat >"$authorization_conf" <<'CONF'
# Keep this custom preamble.
SystemGroup sys root wheel custom-admin wheel # Keep this inline comment.
SystemGroup wheel print-operators # Keep this second inline comment.
PeerCred off # Keep this PeerCred comment.
PeerCred off # Keep this second PeerCred comment.
CONF

log="$test_tmp/actions.log"
export OMARCHY_CUPS_TEST_LOG="$log"

run_printing_setup() {
  PATH="$mock_bin:$PATH" \
    OMARCHY_CUPS_FILES_CONF="$authorization_conf" \
    OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
    bash -euo pipefail "$ROOT/install/config/printing.sh"
}

run_printing_setup

grep -qxF 'SystemGroup sys root custom-admin print-operators cups-browsed # Keep this inline comment.' "$authorization_conf" ||
  fail "printing setup reserves CUPS administration for the service account"
grep -qxF '# Keep this second inline comment.' "$authorization_conf" ||
  fail "printing setup preserves comments from consolidated SystemGroup directives"
grep -qxF 'PeerCred on # Keep this PeerCred comment.' "$authorization_conf" ||
  fail "printing setup enables peer credentials for the service account"
grep -qxF '# Keep this second PeerCred comment.' "$authorization_conf" ||
  fail "printing setup preserves comments from duplicate PeerCred directives"
grep -qxF '# Keep this custom preamble.' "$authorization_conf" ||
  fail "printing setup preserves unrelated CUPS configuration"
[[ $(grep -c '^SystemGroup ' "$authorization_conf") == 1 ]] ||
  fail "printing setup emits one SystemGroup directive"

cp "$authorization_conf" "$test_tmp/first-run.conf"
run_printing_setup
cmp -s "$authorization_conf" "$test_tmp/first-run.conf" ||
  fail "printing setup is idempotent"

pass "printing setup narrows CUPS authorization without clobbering other configuration"

ln -s "$authorization_conf" "$test_tmp/etc/cups/symlinked.conf"
if PATH="$mock_bin:$PATH" \
  OMARCHY_CUPS_FILES_CONF="$test_tmp/etc/cups/symlinked.conf" \
  OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
  bash -euo pipefail "$ROOT/install/config/printing.sh" 2>/dev/null; then
  fail "printing setup refuses a symlinked authorization file"
fi

pass "printing setup refuses to rewrite a symlinked privileged configuration"

marker="$test_tmp/var/lib/omarchy/migrations/1787815267"
PATH="$mock_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_CUPS_FILES_CONF="$authorization_conf" \
  OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
  OMARCHY_CUPS_MIGRATION_MARKER="$marker" \
  bash -euo pipefail "$ROOT/migrations/1787815267.sh"

grep -qxF $'omarchy-pkg-drop\tcups-pdf' "$log" ||
  fail "the migration removes CUPS-PDF"
grep -qxF $'omarchy-pkg-add\tcups-pk-helper' "$log" ||
  fail "the migration installs authenticated printer administration"
grep -qxF $'systemctl\tstop cups-browsed.service' "$log" ||
  fail "the migration stops the root cups-browsed process before reconfiguration"
grep -qxF $'systemctl\tdaemon-reload' "$log" ||
  fail "the migration reloads the hardened service"
grep -qxF $'systemctl\ttry-reload-or-restart cups.service' "$log" ||
  fail "the migration applies narrowed CUPS authorization"
grep -qxF $'systemctl\trestart cups-browsed.service' "$log" ||
  fail "the migration resumes an active cups-browsed service"
[[ -f $marker ]] || fail "the migration records machine-wide completion"

actions_after_first_run=$(wc -l <"$log")
PATH="$mock_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_CUPS_MIGRATION_MARKER="$marker" \
  bash -euo pipefail "$ROOT/migrations/1787815267.sh"
[[ $(wc -l <"$log") == "$actions_after_first_run" ]] ||
  fail "the machine-wide migration repeats privileged work"

pass "the migration safely converts an active existing installation once"

# An interrupted earlier run leaves cups-browsed stopped, so the retry that
# follows finds it inactive. It must still be restarted: the retry records the
# machine-wide marker either way, so a restart skipped here would leave printer
# discovery off until the next reboot with nothing left to run.
cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
[[ $1 == "is-active" ]] && exit 1
exit 0
SH
chmod +x "$mock_bin/systemctl"

retry_log="$test_tmp/retry.log"
retry_marker="$test_tmp/var/lib/omarchy/migrations/1787815267-retry"

OMARCHY_CUPS_TEST_LOG="$retry_log" \
  PATH="$mock_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_CUPS_FILES_CONF="$authorization_conf" \
  OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
  OMARCHY_CUPS_MIGRATION_MARKER="$retry_marker" \
  bash -euo pipefail "$ROOT/migrations/1787815267.sh"

grep -qxF $'systemctl\trestart cups-browsed.service' "$retry_log" ||
  fail "the retry resumes cups-browsed after an interrupted earlier run"

pass "a run following an interrupted one still resumes printer discovery"

# A unit the user masked or disabled reports not-enabled, and restarting it
# would fail and abort the migration before it records completion.
cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$OMARCHY_CUPS_TEST_LOG"
[[ $1 == "is-active" || $1 == "is-enabled" ]] && exit 1
exit 0
SH
chmod +x "$mock_bin/systemctl"

masked_log="$test_tmp/masked.log"
masked_marker="$test_tmp/var/lib/omarchy/migrations/1787815267-masked"

OMARCHY_CUPS_TEST_LOG="$masked_log" \
  PATH="$mock_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_CUPS_FILES_CONF="$authorization_conf" \
  OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
  OMARCHY_CUPS_MIGRATION_MARKER="$masked_marker" \
  bash -euo pipefail "$ROOT/migrations/1787815267.sh"

! grep -qxF $'systemctl\trestart cups-browsed.service' "$masked_log" ||
  fail "the migration leaves a masked or disabled cups-browsed alone"
[[ -f $masked_marker ]] || fail "the migration completes with cups-browsed masked"

pass "a masked or disabled cups-browsed is left alone and does not fail the migration"

# cupsd compares directive names case-insensitively, so a hand-edited lowercase
# directive is live configuration. Matching it exactly would skip the line and
# append a second one, and cupsd accumulates the groups of every SystemGroup
# directive it reads -- leaving wheel with passwordless administration.
lowercase_conf="$test_tmp/etc/cups/lowercase.conf"
cat >"$lowercase_conf" <<'CONF'
systemgroup sys root wheel
peercred off
CONF

PATH="$mock_bin:$PATH" \
  OMARCHY_CUPS_FILES_CONF="$lowercase_conf" \
  OMARCHY_CUPS_BROWSED_SYSUSERS_CONF="$sysusers_conf" \
  bash -euo pipefail "$ROOT/install/config/printing.sh"

! grep -qiE '^[[:space:]]*systemgroup\b.*\bwheel\b' "$lowercase_conf" ||
  fail "printing setup removes wheel from a lowercase SystemGroup directive" "$(cat "$lowercase_conf")"
[[ $(grep -ciE '^[[:space:]]*systemgroup\b' "$lowercase_conf") == 1 ]] ||
  fail "printing setup leaves one SystemGroup directive whatever case it was written in" "$(cat "$lowercase_conf")"
grep -qxF 'SystemGroup sys root cups-browsed' "$lowercase_conf" ||
  fail "printing setup reserves administration for the service account" "$(cat "$lowercase_conf")"
[[ $(grep -ciE '^[[:space:]]*peercred\b' "$lowercase_conf") == 1 ]] ||
  fail "printing setup leaves one PeerCred directive" "$(cat "$lowercase_conf")"
grep -qxF 'PeerCred on' "$lowercase_conf" ||
  fail "printing setup enables peer credentials whatever case they were written in" "$(cat "$lowercase_conf")"

pass "printing setup rewrites directives cupsd reads case-insensitively"
