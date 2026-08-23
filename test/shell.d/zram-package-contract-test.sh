#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command makepkg

ROOT="$ROOT" python3 <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path


def dependency_names(path: Path) -> set[str]:
  try:
    metadata = subprocess.run(
      ["makepkg", "--printsrcinfo"],
      cwd=path.parent,
      check=True,
      capture_output=True,
      text=True,
    ).stdout
  except subprocess.CalledProcessError as error:
    raise ValueError(f"{path}: makepkg --printsrcinfo failed: {error.stderr.strip()}") from error

  dependencies = set()
  for line in metadata.splitlines():
    key, separator, value = line.strip().partition(" = ")
    if separator and (key == "depends" or key.startswith("depends_")):
      dependencies.add(re.split(r"[<>=]", value, maxsplit=1)[0])
  return dependencies


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
