#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home"
export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"
export HOME="$tmp_dir/home"

for stub in omarchy-launch-webapp omarchy-launch-floating-terminal-with-presentation omarchy-openclaw-onboard; do
  cat >"$tmp_dir/bin/$stub" <<SCRIPT
#!/bin/bash
printf '$stub:%s\n' "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$stub"
done

# The retry loop sleeps between polls; a no-op keeps the suite fast.
printf '#!/bin/bash\n' >"$tmp_dir/bin/sleep"
chmod +x "$tmp_dir/bin/sleep"

# The launcher asks systemd whether the gateway unit is enabled; a flag file
# stands in for the user manager.
cat >"$tmp_dir/bin/systemctl" <<SCRIPT
#!/bin/bash
printf 'systemctl:%s\\n' "\$*" >>"\$TEST_LOG"
[[ \$* == *is-enabled* ]] && [[ -f $tmp_dir/gateway-enabled ]]
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

# A machine that never onboarded gets the wizard, not a dashboard probe.
"$ROOT/bin/omarchy-launch-openclaw"

# Through omarchy-openclaw-onboard, never bare `openclaw onboard`, which as of
# 2026.9.1 ends in a browser tab with a foreground gateway and never returns.
grep -q '^omarchy-launch-floating-terminal-with-presentation:omarchy-openclaw-onboard && \[\[ -f \$HOME/.openclaw/openclaw.json \]\] && omarchy-launch-openclaw$' "$TEST_LOG" ||
  fail "OpenClaw launch hands a never-onboarded machine to the wizard" "$(grep floating "$TEST_LOG")"
! grep -q '^omarchy-launch-webapp:' "$TEST_LOG" ||
  fail "OpenClaw launch hands a never-onboarded machine to the wizard" "webapp opened anyway"
pass "OpenClaw launch hands a never-onboarded machine to the wizard"

mkdir -p "$HOME/.openclaw"
touch "$HOME/.openclaw/openclaw.json"

# A running gateway answers the first probe; its handoff URL opens as the app.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
[[ $* == *--json* ]] &&
  echo '{"ok":true,"url":"http://127.0.0.1:18789/?token=shared","browserUrl":"http://127.0.0.1:18789/#handoff"}'
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
"$ROOT/bin/omarchy-launch-openclaw"

grep -q '^omarchy-launch-webapp:http://127.0.0.1:18789/#handoff$' "$TEST_LOG" ||
  fail "OpenClaw launch opens the running gateway's handoff URL"
pass "OpenClaw launch opens the running gateway's handoff URL"

# A machine whose gateway unit was never enabled (never installed, or an
# install that died after writing the unit) gets `gateway install --force`,
# then is polled until the dashboard answers. Never `dashboard --yes`: since
# 2026.9.1 that neither installs nor starts anything and, once the gateway is
# up, pushes a one-time pairing URL into the clipboard.
cat >"$tmp_dir/bin/openclaw" <<SCRIPT
#!/bin/bash
printf 'openclaw:%s\\n' "\$*" >>"\$TEST_LOG"
if [[ \$* == *--json* ]]; then
  [[ -f $tmp_dir/gateway-up ]] || { echo '{"ok":false,"reason":"Gateway is not running."}'; exit 1; }
  echo '{"ok":true,"browserUrl":"http://127.0.0.1:18789/#cold-start"}'
elif [[ \$1 == gateway ]]; then
  touch "$tmp_dir/gateway-up"
fi
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
rm -f "$tmp_dir/gateway-up" "$tmp_dir/gateway-enabled"
mkdir -p "$HOME/.config/systemd/user"
touch "$HOME/.config/systemd/user/openclaw-gateway.service"
: >"$TEST_LOG"
"$ROOT/bin/omarchy-launch-openclaw"

grep -q '^openclaw:gateway install --force$' "$TEST_LOG" ||
  fail "OpenClaw launch installs a never-enabled gateway before opening the app"
! grep -q '^openclaw:gateway start$' "$TEST_LOG" ||
  fail "OpenClaw launch installs a never-enabled gateway before opening the app" "started the half-installed unit instead"
grep -q '^omarchy-launch-webapp:http://127.0.0.1:18789/#cold-start$' "$TEST_LOG" ||
  fail "OpenClaw launch installs a never-enabled gateway before opening the app" "webapp never opened"
pass "OpenClaw launch installs a never-enabled gateway before opening the app"

# An enabled but stopped unit is started, not reinstalled.
touch "$tmp_dir/gateway-enabled"
rm -f "$tmp_dir/gateway-up"
: >"$TEST_LOG"
"$ROOT/bin/omarchy-launch-openclaw"

grep -q '^openclaw:gateway start$' "$TEST_LOG" ||
  fail "OpenClaw launch starts a stopped gateway before opening the app"
! grep -q '^openclaw:gateway install' "$TEST_LOG" ||
  fail "OpenClaw launch starts a stopped gateway before opening the app" "reinstalled the unit"
! grep -q -- '--yes' "$TEST_LOG" ||
  fail "OpenClaw launch starts a stopped gateway before opening the app" "fell back to dashboard --yes"
grep -q '^omarchy-launch-webapp:http://127.0.0.1:18789/#cold-start$' "$TEST_LOG" ||
  fail "OpenClaw launch starts a stopped gateway before opening the app" "webapp never opened"
pass "OpenClaw launch starts a stopped gateway before opening the app"
rm -f "$tmp_dir/gateway-enabled"

# A dashboard probe that hangs is cut off, so the launch still fails cleanly
# instead of sitting forever behind an app-grid icon with no terminal.
cat >"$tmp_dir/bin/timeout" <<SCRIPT
#!/bin/bash
printf 'timeout:%s\\n' "\$1" >>"\$TEST_LOG"
exit 124
SCRIPT
chmod +x "$tmp_dir/bin/timeout"
: >"$TEST_LOG"
rc=0
"$ROOT/bin/omarchy-launch-openclaw" >/dev/null 2>&1 || rc=$?
[[ $rc != 0 ]] || fail "OpenClaw launch bounds a hanging dashboard probe"
grep -q '^timeout:10$' "$TEST_LOG" || fail "OpenClaw launch bounds a hanging dashboard probe" "probe ran without a timeout"
pass "OpenClaw launch bounds a hanging dashboard probe"
rm -f "$tmp_dir/bin/timeout"

# A gateway that never answers fails the launch instead of opening a dead page.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
[[ $* == *--json* ]] && exit 1
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
webapp_calls_before=$(grep -c '^omarchy-launch-webapp:' "$TEST_LOG" || true)
rc=0
"$ROOT/bin/omarchy-launch-openclaw" >/dev/null 2>&1 || rc=$?
webapp_calls_after=$(grep -c '^omarchy-launch-webapp:' "$TEST_LOG" || true)

[[ $rc != 0 ]] || fail "OpenClaw launch fails cleanly when the gateway never comes up"
[[ $webapp_calls_before == "$webapp_calls_after" ]] ||
  fail "OpenClaw launch fails cleanly when the gateway never comes up" "webapp opened anyway"
pass "OpenClaw launch fails cleanly when the gateway never comes up"

# --tui runs onboarding in the terminal it is already in, then attaches to the
# gateway with `openclaw tui` -- never the embedded chat, which the running
# gateway's state-directory lock would refuse.
rm -f "$HOME/.openclaw/openclaw.json"
cat >"$tmp_dir/bin/omarchy-openclaw-onboard" <<SCRIPT
#!/bin/bash
printf 'omarchy-openclaw-onboard:%s\n' "\$*" >>"\$TEST_LOG"
mkdir -p "\$HOME/.openclaw" && touch "\$HOME/.openclaw/openclaw.json"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-openclaw-onboard"
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
[[ $* == *--json* ]] && echo '{"ok":true,"browserUrl":"http://127.0.0.1:18789/#tui"}'
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
floating_calls_before=$(grep -c '^omarchy-launch-floating-terminal-with-presentation:' "$TEST_LOG" || true)
"$ROOT/bin/omarchy-launch-openclaw" --tui

grep -q '^omarchy-openclaw-onboard:$' "$TEST_LOG" ||
  fail "--tui onboards in the current terminal" "$(grep 'onboard' "$TEST_LOG")"
floating_calls_after=$(grep -c '^omarchy-launch-floating-terminal-with-presentation:' "$TEST_LOG" || true)
[[ $floating_calls_before == "$floating_calls_after" ]] ||
  fail "--tui onboards in the current terminal" "spawned a floating terminal"
grep -q '^openclaw:tui$' "$TEST_LOG" || fail "--tui attaches to the gateway"
pass "--tui onboards in place and attaches to the gateway"

# The stub also logs argv one entry per line, so a prompt split into words
# would show up as extra lines rather than pass a space-joined comparison.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
[[ $1 == tui ]] && printf 'argv:[%s]\n' "$@" >>"$TEST_LOG"
[[ $* == *--json* ]] && echo '{"ok":true,"browserUrl":"http://127.0.0.1:18789/#tui"}'
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
: >"$TEST_LOG"
"$ROOT/bin/omarchy-launch-openclaw" --tui --message "Review this project"
[[ $(grep -c '^argv:' "$TEST_LOG") == 3 ]] && grep -q '^argv:\[Review this project\]$' "$TEST_LOG" ||
  fail "--tui seeds the session through --message" "$(grep '^argv:' "$TEST_LOG" | tr '\n' ' ')"
! grep -q '^omarchy-launch-webapp:' "$TEST_LOG" ||
  fail "--tui seeds the session through --message" "webapp opened instead"
pass "--tui seeds the session through --message"
