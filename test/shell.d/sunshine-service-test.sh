#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
home="$tmpdir/home"
log="$tmpdir/commands.log"
mkdir -p "$stub_bin" "$home"

for command in systemctl omarchy-pkg-add omarchy-pkg-drop omarchy-webapp-install omarchy-webapp-remove omarchy-launch-webapp; do
  cat >"$stub_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$TEST_LOG"
SH
  chmod +x "$stub_bin/$command"
done

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-cmd-missing"

run_sunshine_command() {
  TEST_LOG="$log" HOME="$home" PATH="$stub_bin:$PATH" bash "$1" >/dev/null
}

run_sunshine_command "$ROOT/bin/omarchy-install-service-sunshine"
grep -qFx "systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service" "$log" ||
  fail "Sunshine install enables the packaged user unit" "$(cat "$log")"
pass "Sunshine install enables the packaged user unit"

: >"$log"
run_sunshine_command "$ROOT/bin/omarchy-remove-service-sunshine"
grep -qFx "systemctl --user disable --now app-dev.lizardbyte.app.Sunshine.service" "$log" ||
  fail "Sunshine removal disables the packaged user unit" "$(cat "$log")"
pass "Sunshine removal disables the packaged user unit"
