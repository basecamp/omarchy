#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_home=$(mktemp -d)
hooks_dir="$test_home/.config/omarchy/hooks/post-update.d"
migration="$ROOT/migrations/1787689809.sh"

cleanup() {
  rm -rf "$test_home"
}
trap cleanup EXIT

mkdir -p "$hooks_dir"

cat >"$hooks_dir/setup-agent.hook" <<'EOF'
#!/bin/bash
# Keep this customization.
omarchy-notification-send "Agent" --exec "omarchy menu summon setup.default.agent"
EOF

cat >"$hooks_dir/install-voxtype.hook" <<'EOF'
#!/bin/bash
omarchy-notification-send "Voxtype" \
  --exec "omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install"
EOF

fingerprint_target="$test_home/custom-fingerprint-hook"
cat >"$fingerprint_target" <<'EOF'
#!/bin/bash
omarchy-notification-send "Fingerprint" --exec "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint"
EOF
ln -s "$fingerprint_target" "$hooks_dir/setup-fingerprint.hook"

chmod 755 "$hooks_dir/setup-agent.hook" "$hooks_dir/install-voxtype.hook" "$fingerprint_target"

HOME="$test_home" bash -euo pipefail "$migration" >/dev/null
HOME="$test_home" bash -euo pipefail "$migration" >/dev/null

grep -Fq -- '--exec omarchy menu summon setup.default.agent' "$hooks_dir/setup-agent.hook" ||
  fail "migration updates the agent invitation click action"
grep -Fq -- '--exec omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install' "$hooks_dir/install-voxtype.hook" ||
  fail "migration updates the Voxtype invitation click action"
grep -Fq -- '# Keep this customization.' "$hooks_dir/setup-agent.hook" ||
  fail "migration preserves hook customizations"

if grep -Fq -- '--exec "' "$hooks_dir/setup-agent.hook" "$hooks_dir/install-voxtype.hook"; then
  fail "migration leaves a shipped command-string click action"
fi

grep -Fq -- '--exec "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint"' "$fingerprint_target" ||
  fail "migration leaves symlinked development hooks alone"

[[ $(stat -c '%a' "$hooks_dir/setup-agent.hook") == "755" ]] ||
  fail "migration preserves executable hook permissions"

pass "invitation hook argv migration is targeted and idempotent"
