#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

ROOT="$ROOT" python3 <<'PY'
import os
import re
import shlex
import sys
from pathlib import Path


def pkgbuild_array(path: Path, name: str) -> list[str]:
  text = path.read_text()
  match = re.search(
    rf"^[ \t]*{re.escape(name)}=\([ \t]*\n(.*?)^[ \t]*\)",
    text,
    flags=re.MULTILINE | re.DOTALL,
  )
  if match is None:
    raise ValueError(f"{path}: missing {name}=() array")

  lexer = shlex.shlex(match.group(1), posix=True)
  lexer.commenters = "#"
  lexer.whitespace_split = True
  return list(lexer)


def dependency_names(path: Path) -> set[str]:
  return {re.split(r"[<>=]", item, maxsplit=1)[0] for item in pkgbuild_array(path, "depends")}


root = Path(os.environ["ROOT"])
home = Path.home()
pkgs_candidates = [
  root.parent / "omarchy-pkgs/pkgbuilds",
  root.parent / "omarchy/omarchy-pkgs/pkgbuilds",
  root.parent.parent / "omarchy-pkgs/pkgbuilds",
  root.parent / "omacom/omarchy-pkgs/pkgbuilds",
  root.parent.parent / "omacom/omarchy-pkgs/pkgbuilds",
  home / "Work/omacom/omarchy-pkgs/pkgbuilds",
]
override = os.environ.get("OMARCHY_PKGS_PATH")
if override:
  pkgs_candidates = [Path(override) / "pkgbuilds", Path(override)] + pkgs_candidates

pkgs_root = next((path for path in pkgs_candidates if path.is_dir()), None)
if pkgs_root is None:
  print("not ok - omarchy-pkgs checkout found for zram package coverage", file=sys.stderr)
  print(
    "looked in:\n  " + "\n  ".join(str(path) for path in pkgs_candidates) +
    "\nset OMARCHY_PKGS_PATH to the omarchy-pkgs checkout",
    file=sys.stderr,
  )
  sys.exit(1)

errors = []
target_packages = ("omarchy", "omarchy-dev")
settings_packages = ("omarchy-settings", "omarchy-settings-dev")

for package in target_packages + settings_packages:
  pkgbuild = pkgs_root / package / "PKGBUILD"
  if not pkgbuild.is_file():
    errors.append(f"missing PKGBUILD: {pkgbuild}")
    continue

  try:
    dependencies = dependency_names(pkgbuild)
  except ValueError as error:
    errors.append(str(error))
    continue

  if package in target_packages and "zram-generator" not in dependencies:
    errors.append(f"{package} must hard-depend on zram-generator")
  if package in settings_packages and "zram-generator" in dependencies:
    errors.append(
      f"{package} must not hard-depend on zram-generator because it is installed in the live ISO"
    )

other_packages = {
  line.split("#", 1)[0].strip()
  for line in (root / "install/omarchy-other.packages").read_text().splitlines()
  if line.split("#", 1)[0].strip()
}
if "zram-generator" not in other_packages:
  errors.append("install/omarchy-other.packages must keep zram-generator available to the ISO builder")

if errors:
  print("\n".join(errors), file=sys.stderr)
  sys.exit(1)
PY

pass "target packages require zram-generator without making settings unsafe for the live ISO"
