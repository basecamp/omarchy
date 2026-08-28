#!/bin/bash

set -euo pipefail

matrix=${1:?representative outcome matrix is required}

python3 - "$matrix" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
  report = json.load(source)

if report.get("schemaVersion") != 1 or report.get("advisoryOnly") is not True:
  raise SystemExit("representative report lost its advisory schema")
if report.get("legacySchemaV1Safe") is not False:
  raise SystemExit("representative report claimed schema-v1 safety")

corpus = report.get("corpus", {})
cases = report.get("cases", [])
if corpus.get("sources") != 1575 or corpus.get("catalogEntries") != 1613:
  raise SystemExit("pinned marketplace corpus counts changed")
if corpus.get("sampleSize") != 20 or len(cases) != 20:
  raise SystemExit("representative sample must contain exactly 20 pinned cases")

ids = [case.get("id") for case in cases]
if len(set(ids)) != len(ids):
  raise SystemExit("representative sample contains duplicate plugin ids")

passed = [case for case in cases if case.get("scan", {}).get("status") == "passed"]
blocked = [case for case in cases if case.get("scan", {}).get("status") == "blocked"]
if len(passed) != corpus.get("scannerPassed") or len(blocked) != corpus.get("scannerBlocked"):
  raise SystemExit("scanner pass/block totals disagree with the pinned corpus run")
if (len(passed), len(blocked)) != (14, 6):
  raise SystemExit("unexpected representative scanner outcome")

required_categories = {
  "bar-widget", "bar", "panel", "overlay", "service", "network",
  "filesystem", "notification", "media", "exec", "hostile-ambiguous",
}
categories = {category for case in cases for category in case.get("categories", [])}
missing = sorted(required_categories - categories)
if missing:
  raise SystemExit(f"representative behavior coverage is missing: {missing}")

for case in cases:
  if not re.fullmatch(r"[0-9a-f]{40}", case.get("commit", "")):
    raise SystemExit(f"{case.get('id')} lacks a pinned source commit")
  scan = case.get("scan", {})
  if scan.get("status") == "passed":
    if not re.fullmatch(r"[0-9a-f]{64}", scan.get("snapshot", "")):
      raise SystemExit(f"{case['id']} lacks an exact scanner snapshot")
    if not isinstance(scan.get("findings"), int) or scan["findings"] <= 0:
      raise SystemExit(f"{case['id']} has an invalid finding count")
    if not scan.get("findingIds"):
      raise SystemExit(f"{case['id']} lost its observed finding classes")
  elif "1048576-byte scan limit" not in scan.get("error", ""):
    raise SystemExit(f"{case['id']} scanner blocker is not explicit")

  target = case.get("tomorrow", {})
  if not str(target.get("arbitraryQml", "")).startswith("retained"):
    raise SystemExit(f"{case['id']} lost arbitrary-QML compatibility")
  if not target.get("authorities") or not target.get("status"):
    raise SystemExit(f"{case['id']} lacks an exact target authority/status")
  forbidden = {"exec", "process.exec", "shell.exec", "filesystem", "network", "dbus", "wayland"}
  if forbidden.intersection(target["authorities"]):
    raise SystemExit(f"{case['id']} proposes ambient authority")

proofs = {
  case.get("tomorrow", {}).get("proof") or case.get("tomorrow", {}).get("proofAnalogue")
  for case in cases
}
if not {"E1", "E2 transparent pet", "E3 service.fake-status@1"}.issubset(proofs):
  raise SystemExit("the three attempted migration lanes are not tied to executable proofs")

manual_gaps = {case["id"] for case in cases if case.get("scan", {}).get("manualGap")}
if manual_gaps != {"djjeane.docker-monitor", "jltrench.textify"}:
  raise SystemExit("known scanner false-negative evidence changed")

if next(case for case in cases if case["id"] == "b.okomart")["tomorrow"]["status"] != "trusted-host-product":
  raise SystemExit("plugin lifecycle management was downgraded to plugin authority")
if next(case for case in cases if case["id"] == "lacuna.shell-suite")["tomorrow"]["status"] != "different-trust-class":
  raise SystemExit("complete shell suite was misclassified as an ordinary plugin")

print("representative plugin migration dry runs: PASS")
PY
