#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

SCANNER="$ROOT/bin/omarchy-plugin-security-scan"
FIXTURE="$ROOT/test/shell.d/fixtures/plugin-security-inventory"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

require_command python3

cp -a "$FIXTURE/plugin" "$TEST_TMP/plugin"

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
    relative = os.path.relpath(path, root).encode()
    metadata = os.lstat(path)
    digest.update(relative + b"\0" + str(stat.S_IMODE(metadata.st_mode)).encode() + b"\0")
    if stat.S_ISLNK(metadata.st_mode):
      digest.update(os.readlink(path).encode())
    elif stat.S_ISREG(metadata.st_mode):
      with open(path, "rb") as source:
        digest.update(source.read())
print(digest.hexdigest())
PY
}

before=$(tree_fingerprint "$TEST_TMP/plugin")
INVENTORY_EXECUTION_MARKER="$TEST_TMP/executed" "$SCANNER" "$TEST_TMP/plugin" --format json >"$TEST_TMP/report.json"
after=$(tree_fingerprint "$TEST_TMP/plugin")

if [[ $before != "$after" ]]; then
  fail "inventory scan leaves plugin content and modes unchanged"
else
  pass "inventory scan leaves plugin content and modes unchanged"
fi

if [[ -e $TEST_TMP/executed ]]; then
  fail "inventory scan never executes plugin content"
else
  pass "inventory scan never executes plugin content"
fi

if ! python3 - "$TEST_TMP/report.json" "$FIXTURE/expected.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
  actual = json.load(source)
with open(sys.argv[2], encoding="utf-8") as source:
  expected = json.load(source)

projection = {
  "plugin": actual["plugin"],
  "summary": actual["summary"],
  "findings": [
    [item["id"], item["severity"], item["path"], item["line"], item["confidence"]]
    for item in actual["findings"]
  ],
}
if projection != expected:
  print("expected:", json.dumps(expected, indent=2, sort_keys=True), file=sys.stderr)
  print("actual:", json.dumps(projection, indent=2, sort_keys=True), file=sys.stderr)
  raise SystemExit(1)
if actual.get("schemaVersion") != 1 or actual.get("advisoryOnly") is not True:
  raise SystemExit("report identity is not advisory schema v1")
if any(item["authorDecision"] != "review required" for item in actual["findings"]):
  raise SystemExit("a finding implied an automatic author decision")
if any(item["path"] == "comments.qml" for item in actual["findings"]):
  raise SystemExit("comment-only examples produced findings")
PY
then
  fail "fixture inventory matches the frozen taxonomy"
else
  pass "fixture inventory matches the frozen taxonomy"
fi
if grep -Fq 'B7_SECRET_MUST_NOT_LEAK' "$TEST_TMP/report.json"; then
  fail "inventory report redacts source content"
else
  pass "inventory report redacts source content"
fi

"$SCANNER" "$TEST_TMP/plugin" --format markdown >"$TEST_TMP/worksheet.md"
if ! grep -Fq '| Detected behavior | Proposed broker/UI mapping | Author decision |' "$TEST_TMP/worksheet.md" ||
   ! grep -Fq 'Advisory static inventory only' "$TEST_TMP/worksheet.md" ||
   ! grep -Fq 'Review: ☐ keep ☐ narrow ☐ replace ☐ remove' "$TEST_TMP/worksheet.md"; then
  fail "markdown output is an advisory three-column migration worksheet"
else
  pass "markdown output is an advisory three-column migration worksheet"
fi

ln -s /etc/passwd "$TEST_TMP/plugin/external-link"
mkfifo "$TEST_TMP/plugin/special.pipe"
printf '\177ELFfixture' >"$TEST_TMP/plugin/helper.so"
"$SCANNER" "$TEST_TMP/plugin" --format json >"$TEST_TMP/special-report.json"
if ! python3 - "$TEST_TMP/special-report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
  identifiers = {item["id"] for item in json.load(source)["findings"]}
if not {"filesystem.symlink", "filesystem.special", "native.binary"}.issubset(identifiers):
  raise SystemExit(1)
PY
then
  fail "scanner reports symlinks, special files, and native binaries without executing them"
else
  pass "scanner reports symlinks, special files, and native binaries without executing them"
fi

truncate -s 1048577 "$TEST_TMP/plugin/oversize.qml"
if "$SCANNER" "$TEST_TMP/plugin" --format json >"$TEST_TMP/oversize.json" 2>"$TEST_TMP/oversize.err"; then
  fail "scanner fails closed when a file exceeds its byte bound"
else
  pass "scanner fails closed when a file exceeds its byte bound"
fi
if ! grep -Fq '1048576-byte scan limit' "$TEST_TMP/oversize.err"; then
  fail "scanner explains its per-file bound"
else
  pass "scanner explains its per-file bound"
fi

ln -s "$FIXTURE/plugin" "$TEST_TMP/plugin-root-link"
if "$SCANNER" "$TEST_TMP/plugin-root-link" --format json >"$TEST_TMP/link.json" 2>"$TEST_TMP/link.err"; then
  fail "scanner rejects a symlink as its plugin root"
else
  pass "scanner rejects a symlink as its plugin root"
fi

cp -a "$FIXTURE/plugin" "$TEST_TMP/duplicate-manifest"
printf '{"id":"one","id":"two"}\n' >"$TEST_TMP/duplicate-manifest/plugin.json"
"$SCANNER" "$TEST_TMP/duplicate-manifest" --format json >"$TEST_TMP/duplicate.json"
if ! python3 - "$TEST_TMP/duplicate.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
  findings = json.load(source)["findings"]
if not any(item["id"] == "manifest.invalid" and "duplicate key" in item["behavior"] for item in findings):
  raise SystemExit(1)
PY
then
  fail "strict manifest inventory rejects duplicate JSON keys"
else
  pass "strict manifest inventory rejects duplicate JSON keys"
fi
