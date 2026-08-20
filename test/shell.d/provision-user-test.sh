#!/bin/bash
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"
cat >"$mock_bin/xdg-user-dirs-update" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/omarchy-refresh-applications" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/xdg-mime" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$ROOT/install" \
  bash "$ROOT/bin/omarchy-provision-user" >/dev/null

[[ -L "$test_tmp/home/.gemini/config/skills/omarchy" && $(readlink "$test_tmp/home/.gemini/config/skills/omarchy") == "$ROOT/default/agents/skills/omarchy" ]] ||
   fail "omarchy-provision-user provisions the omarchy skill for Antigravity"

pass "omarchy-provision-user provisions Antigravity skills"
