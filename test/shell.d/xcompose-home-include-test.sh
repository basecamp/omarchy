#!/bin/bash

set -euo pipefail

# Absolute includes into /usr/share/omarchy break compose inside sandboxes that
# only bind-mount $HOME. The install leaf must seed a home-local table and
# point ~/.XCompose at it with %H.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
packaged_root="$test_tmp/omarchy"
mkdir -p "$home" "$packaged_root/default" "$packaged_root/install/user"

cat >"$packaged_root/default/xcompose" <<'EOF'
include "%L"
<Multi_key> <m> <s> : "smile"
EOF

cp "$ROOT/install/user/xcompose.sh" "$packaged_root/install/user/xcompose.sh"

HOME="$home" OMARCHY_PATH="$packaged_root" OMARCHY_USER_NAME="Test User" \
  OMARCHY_USER_EMAIL="test@example.com" \
  bash -c 'source "$OMARCHY_PATH/install/user/xcompose.sh"'

[[ -f $home/.XCompose.omarchy ]] || fail "install seeds ~/.XCompose.omarchy from the packaged table"
grep -Fq 'Multi_key> <m> <s>' "$home/.XCompose.omarchy" \
  || fail "the home-local table is the packaged emoji file"

[[ -f $home/.XCompose ]] || fail "install writes ~/.XCompose"
grep -Eq '^[[:space:]]*include[[:space:]]+"%H/\.XCompose\.omarchy"' "$home/.XCompose" \
  || fail "~/.XCompose includes the home-local table via %H" "$(cat "$home/.XCompose")"
! grep -E 'include[[:space:]]+"/usr/share/omarchy' "$home/.XCompose" \
  || fail "~/.XCompose must not use an absolute /usr/share/omarchy include" "$(cat "$home/.XCompose")"

pass "install/user/xcompose.sh seeds a %H-relative home-local include"

# Migration rewrites an existing absolute include and refreshes the home copy.
abs_home="$test_tmp/abs-home"
mkdir -p "$abs_home"
cat >"$abs_home/.XCompose" <<'EOF'
# Run omarchy-restart-xcompose to apply changes

include "/usr/share/omarchy/default/xcompose"

<Multi_key> <space> <n> : "Keep Me"
EOF

# Migration calls omarchy-restart-xcompose; stub it so the unit manager is not required.
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/omarchy-restart-xcompose" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin/omarchy-restart-xcompose"

HOME="$abs_home" OMARCHY_PATH="$packaged_root" PATH="$mock_bin:$PATH" \
  bash "$ROOT/migrations/1788138200.sh"

[[ -f $abs_home/.XCompose.omarchy ]] || fail "migration copies the packaged table into the home"
grep -Eq '^[[:space:]]*include[[:space:]]+"%H/\.XCompose\.omarchy"' "$abs_home/.XCompose" \
  || fail "migration rewrites the absolute include to %H/.XCompose.omarchy" "$(cat "$abs_home/.XCompose")"
grep -Fq 'Keep Me' "$abs_home/.XCompose" \
  || fail "migration preserves the user's own compose sequences"

pass "migration rewrites absolute XCompose includes without dropping user sequences"

# A missing include target must fail compile; the home-local form must succeed
# when only $HOME is visible (the Steam/pressure-vessel shape). Skip when this
# xkbcli build has no compile-compose subcommand (common on non-Arch packages).
if command -v xkbcli >/dev/null 2>&1 && xkbcli compile-compose --help >/dev/null 2>&1; then
  bad="$test_tmp/bad.compose"
  cat >"$bad" <<'EOF'
include "/usr/share/omarchy/does-not-exist-for-repro"
EOF
  if xkbcli compile-compose --file "$bad" >/dev/null 2>&1; then
    fail "xkbcli rejects a compose file whose include cannot be opened"
  fi

  good_home="$test_tmp/good-home"
  mkdir -p "$good_home"
  # Avoid include "%L" so the check does not depend on a full locale compose
  # database in the test environment — only on %H expansion under $HOME.
  cat >"$good_home/.XCompose.omarchy" <<'EOF'
<Multi_key> <m> <s> : "ok"
EOF
  cat >"$good_home/.XCompose" <<'EOF'
include "%H/.XCompose.omarchy"
EOF
  HOME="$good_home" xkbcli compile-compose --file "$good_home/.XCompose" >/dev/null 2>&1 \
    || fail "xkbcli accepts a %H-relative include that resolves under \$HOME"

  pass "xkbcli accepts home-local includes and rejects missing absolute ones"
else
  pass "xkbcli compile-compose not available; skipped parser checks"
fi
