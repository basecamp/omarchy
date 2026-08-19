#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787085233.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
autostart_dir="$test_home/.config/autostart"
fake_bin="$test_dir/bin"
calls="$test_dir/calls"
mkdir -p "$autostart_dir" "$fake_bin"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash

printf 'systemctl %s\n' "$*" >>"$CALLS"
[[ $* == "--user is-active --quiet graphical-session.target" && ${ACTIVE_SESSION:-no} == "yes" ]]
STUB

cat >"$fake_bin/omarchy-restart-xcompose" <<'STUB'
#!/bin/bash

printf 'omarchy-restart-xcompose\n' >>"$CALLS"
[[ ${RESTART_FAIL:-no} != "yes" ]]
STUB

chmod +x "$fake_bin/"*

run_migration() {
  : >"$calls"
  ACTIVE_SESSION="${1:-no}" \
    RESTART_FAIL="${2:-no}" \
    CALLS="$calls" \
    HOME="$test_home" \
    PATH="$fake_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

cat >"$autostart_dir/fcitx5.desktop" <<'EOF'
[Desktop Entry]
Name=Custom input method
Exec=fcitx5 -d
X-Custom=preserve-me
EOF

cat >"$autostart_dir/input-method.desktop" <<'EOF'
[Desktop Entry]
Name=Absolute input method
Exec="/usr/bin/fcitx5" --replace
Hidden=false
EOF

cat >"$autostart_dir/empty-hidden.desktop" <<'EOF'
[Desktop Entry]
Name=Input method with an empty hidden key
Exec=fcitx5
Hidden=
EOF

cat >"$autostart_dir/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Hidden=true
EOF
stock_mask_before=$(sha256sum "$autostart_dir/org.fcitx.Fcitx5.desktop")

cat >"$autostart_dir/fcitx5-config.desktop" <<'EOF'
[Desktop Entry]
Name=Fcitx configuration
Exec=fcitx5-configtool
EOF
config_entry_before=$(sha256sum "$autostart_dir/fcitx5-config.desktop")

cat >"$autostart_dir/action-only.desktop" <<'EOF'
[Desktop Entry]
Name=Input method helper
Exec=input-method-helper

[Desktop Action Restart]
Name=Restart fcitx5
Exec=fcitx5 --replace
EOF
action_entry_before=$(sha256sum "$autostart_dir/action-only.desktop")

run_migration no

grep -qxF 'Hidden=true' "$autostart_dir/fcitx5.desktop" ||
  fail "migration disables a differently named fcitx5 autostart"
grep -qxF 'X-Custom=preserve-me' "$autostart_dir/fcitx5.desktop" ||
  fail "migration preserves custom desktop entry fields"
grep -qxF 'Hidden=true' "$autostart_dir/input-method.desktop" ||
  fail "migration disables an absolute fcitx5 launch and replaces Hidden=false"
[[ $(grep -c '^Hidden=' "$autostart_dir/empty-hidden.desktop") == 1 ]] &&
  grep -qxF 'Hidden=true' "$autostart_dir/empty-hidden.desktop" ||
  fail "migration replaces an empty Hidden key without duplicating it"
pass "migration disables competing fcitx5 autostarts without deleting them"

[[ $(sha256sum "$autostart_dir/org.fcitx.Fcitx5.desktop") == "$stock_mask_before" ]] ||
  fail "migration leaves the packaged fcitx5 mask alone"
[[ $(sha256sum "$autostart_dir/fcitx5-config.desktop") == "$config_entry_before" ]] ||
  fail "migration leaves related fcitx5 tools alone"
[[ $(sha256sum "$autostart_dir/action-only.desktop") == "$action_entry_before" ]] ||
  fail "migration ignores fcitx5 commands outside the main desktop entry"
pass "migration only changes desktop entries that launch fcitx5"

if grep -qFx 'omarchy-restart-xcompose' "$calls"; then
  fail "migration restarts fcitx5 outside a graphical session"
fi
pass "migration defers service repair outside a graphical session"

sed -i '/^Hidden=true$/d' "$autostart_dir/fcitx5.desktop"
run_migration yes

grep -qFx 'omarchy-restart-xcompose' "$calls" ||
  fail "migration repairs the running service after disabling a competing autostart" "$(cat "$calls")"
pass "migration repairs fcitx5 in an active graphical session"

before=$(find "$autostart_dir" -type f -print0 | sort -z | xargs -0 sha256sum)
run_migration yes
after=$(find "$autostart_dir" -type f -print0 | sort -z | xargs -0 sha256sum)

[[ $before == "$after" ]] || fail "fcitx5 autostart migration is idempotent"
grep -qFx 'omarchy-restart-xcompose' "$calls" ||
  fail "migration keeps repairing the service when its prior restart may have failed" "$(cat "$calls")"
pass "fcitx5 autostart migration is idempotent and retryable"

if run_migration yes yes; then
  fail "migration reports success when the fcitx5 service repair fails"
fi

run_migration yes
grep -qFx 'omarchy-restart-xcompose' "$calls" ||
  fail "migration retries the service repair after a failure" "$(cat "$calls")"
pass "migration keeps a failed service repair retryable"
