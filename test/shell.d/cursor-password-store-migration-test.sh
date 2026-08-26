#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command python3

migration="$ROOT/migrations/1787689809.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
stub_bin="$test_dir/bin"
mkdir -p "$home" "$stub_bin"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_CURSOR_PRESENT:-0} == 1 ]]
SH
chmod +x "$stub_bin/omarchy-cmd-present"

run_migration() {
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

run_migration
[[ ! -e $home/.cursor ]] || fail "migration ignores machines without Cursor"
pass "migration ignores machines without Cursor"

OMARCHY_TEST_CURSOR_PRESENT=1 run_migration
grep -Fq '"password-store": "gnome-libsecret"' "$home/.cursor/argv.json" ||
  fail "migration writes argv.json when Cursor is installed but has never launched"
pass "migration writes argv.json when Cursor is installed but has never launched"

rm -rf "$home/.cursor"
mkdir -p "$home/.cursor"
cat >"$home/.cursor/argv.json" <<'EOF'
// NOTE: Changing this file requires a restart of VS Code.
{
	"enable-crash-reporter": true,
	"crash-reporter-id": "keep-me"
}
EOF

run_migration
grep -Fq '"crash-reporter-id": "keep-me"' "$home/.cursor/argv.json" ||
  fail "migration preserves existing argv.json keys"
grep -Fq '"password-store": "gnome-libsecret"' "$home/.cursor/argv.json" ||
  fail "migration inserts gnome-libsecret into an existing argv.json"
python3 -c 'import json,pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text()
text=re.sub(r"//.*?$", "", text, flags=re.M)
json.loads(text)
' "$home/.cursor/argv.json" || fail "migrated argv.json stays parseable"
pass "migration inserts gnome-libsecret into an existing argv.json"

cat >"$home/.cursor/argv.json" <<'EOF'
{
  "password-store": "basic",
  "crash-reporter-id": "keep-me"
}
EOF

run_migration
grep -Fq '"password-store": "basic"' "$home/.cursor/argv.json" ||
  fail "migration leaves an explicit password-store alone"
if grep -Fq 'gnome-libsecret' "$home/.cursor/argv.json"; then
  fail "migration leaves an explicit password-store alone"
fi
pass "migration leaves an explicit password-store alone"
