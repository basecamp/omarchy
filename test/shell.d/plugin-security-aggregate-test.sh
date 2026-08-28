#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

SCANNER="$ROOT/bin/omarchy-plugin-security-scan"
FIXTURE="$ROOT/test/shell.d/fixtures/plugin-security-aggregate"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

require_command python3

cp -a "$FIXTURE/installed" "$TEST_TMP/installed"
cp -a "$FIXTURE/builtin" "$TEST_TMP/builtin"
mkdir "$TEST_TMP/installed/.staging"
printf '#!/bin/bash\ntouch "$INVENTORY_EXECUTION_MARKER"\n' >"$TEST_TMP/installed/.staging/install.sh"
chmod +x "$TEST_TMP/installed/.staging/install.sh"
ln -s /etc "$TEST_TMP/installed/linked"

tree_fingerprint() {
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys

root = sys.argv[1]
digest = hashlib.sha256()
for directory, directories, files in os.walk(root, followlinks=False):
  directories.sort()
  files.sort()
  for name in directories + files:
    path = os.path.join(directory, name)
    metadata = os.lstat(path)
    digest.update(os.path.relpath(path, root).encode() + b"\0")
    digest.update(str(stat.S_IMODE(metadata.st_mode)).encode() + b"\0")
    if stat.S_ISLNK(metadata.st_mode):
      digest.update(os.readlink(path).encode())
    elif stat.S_ISREG(metadata.st_mode):
      with open(path, "rb") as source:
        digest.update(source.read())
print(digest.hexdigest())
PY
}

before_installed=$(tree_fingerprint "$TEST_TMP/installed")
before_builtin=$(tree_fingerprint "$TEST_TMP/builtin")
INVENTORY_EXECUTION_MARKER="$TEST_TMP/executed" "$SCANNER" --all \
  --installed-root "$TEST_TMP/installed" --builtin-root "$TEST_TMP/builtin" \
  --format json >"$TEST_TMP/report.json"
after_installed=$(tree_fingerprint "$TEST_TMP/installed")
after_builtin=$(tree_fingerprint "$TEST_TMP/builtin")

if [[ $before_installed != "$after_installed" || $before_builtin != "$after_builtin" ]]; then
  fail "aggregate inventory leaves every plugin root unchanged"
else
  pass "aggregate inventory leaves every plugin root unchanged"
fi
if [[ -e $TEST_TMP/executed ]]; then
  fail "aggregate inventory never executes hidden staging or plugin content"
else
  pass "aggregate inventory never executes hidden staging or plugin content"
fi

if ! python3 - "$TEST_TMP/report.json" "$FIXTURE/expected.json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
  actual = json.load(source)
with open(sys.argv[2], encoding="utf-8") as source:
  expected = json.load(source)

roots = [
  [item["kind"], item["status"], item.get("discoveredPlugins", 0), item.get("ignoredHiddenEntries", 0)]
  for item in actual["roots"]
]
plugins = []
for item in actual["plugins"]:
  report = item.get("report", {})
  identity = item.get("revisionIdentity")
  plugins.append([
    item["sourceKind"],
    item["sourcePath"],
    item["status"],
    item.get("plugin"),
    identity.get("sha256") if identity else None,
    [finding["id"] for finding in report.get("findings", [])],
  ])
  if item["status"] == "scanned":
    if report.get("advisoryOnly") is not True or report.get("legacySchemaV1Safe") is not False:
      raise SystemExit("nested report changed advisory/v1-unsafe identity")
    if identity.get("kind") != "advisory-content-snapshot-v1" or not re.fullmatch(r"[0-9a-f]{64}", identity.get("sha256", "")):
      raise SystemExit("revision snapshot identity is absent or overstated")

projection = {"roots": roots, "summary": actual["summary"], "plugins": plugins}
if projection != expected:
  print("expected:", json.dumps(expected, indent=2, sort_keys=True), file=sys.stderr)
  print("actual:", json.dumps(projection, indent=2, sort_keys=True), file=sys.stderr)
  raise SystemExit(1)
if actual.get("reportType") != "installed-plugin-migration-inventory" or actual.get("advisoryOnly") is not True or actual.get("legacySchemaV1Safe") is not False:
  raise SystemExit("aggregate report changed advisory/v1-unsafe identity")
if actual["plugins"][3].get("reason") != "symlink-plugin-root":
  raise SystemExit("symlinked plugin root was not explicitly blocked")
PY
then
  fail "aggregate inventory matches frozen identities, findings, and incomplete states"
else
  pass "aggregate inventory matches frozen identities, findings, and incomplete states"
fi

"$SCANNER" --all --installed-root "$TEST_TMP/installed" \
  --builtin-root "$TEST_TMP/builtin" --format markdown >"$TEST_TMP/worksheet.md"
if ! grep -Fq 'Schema v1 plugins remain unsafe host code' "$TEST_TMP/worksheet.md" ||
   ! grep -Fq 'Scan blocked: `symlink-plugin-root`' "$TEST_TMP/worksheet.md" ||
   ! grep -Fq 'advisory content snapshot' "$TEST_TMP/worksheet.md"; then
  fail "aggregate worksheet preserves unsafe, blocked, and advisory identity warnings"
else
  pass "aggregate worksheet preserves unsafe, blocked, and advisory identity warnings"
fi

"$SCANNER" --all --installed-root "$TEST_TMP/missing-installed" \
  --builtin-root "$TEST_TMP/missing-builtin" --format json >"$TEST_TMP/absent.json"
if ! python3 - "$TEST_TMP/absent.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
  report = json.load(source)
if [root["status"] for root in report["roots"]] != ["absent", "absent"]:
  raise SystemExit(1)
if report["summary"] != {"blocked": 0, "discovered": 0, "findings": 0, "scanned": 0, "severity": {"critical": 0, "high": 0, "info": 0, "medium": 0, "review": 0}}:
  raise SystemExit(1)
PY
then
  fail "absent roots produce an explicit empty advisory inventory"
else
  pass "absent roots produce an explicit empty advisory inventory"
fi

ln -s "$TEST_TMP/builtin" "$TEST_TMP/builtin-link"
"$SCANNER" --all --installed-root "$TEST_TMP/missing-installed" \
  --builtin-root "$TEST_TMP/builtin-link" --format json >"$TEST_TMP/root-link.json"
if ! grep -Fq 'root-is-symlink-unreadable-or-not-directory' "$TEST_TMP/root-link.json"; then
  fail "symlinked aggregate root is blocked without traversal"
else
  pass "symlinked aggregate root is blocked without traversal"
fi

if "$SCANNER" --all --enable example.alpha >"$TEST_TMP/enable.out" 2>"$TEST_TMP/enable.err" ||
   "$SCANNER" --all --grant storage.private >"$TEST_TMP/grant.out" 2>"$TEST_TMP/grant.err"; then
  fail "aggregate inventory exposes no enable or grant action"
else
  pass "aggregate inventory exposes no enable or grant action"
fi
