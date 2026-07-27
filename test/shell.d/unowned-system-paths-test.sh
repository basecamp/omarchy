#!/bin/bash

# A file Omarchy writes into /usr belongs to nobody, and the
# day a package starts shipping that same path, pacman refuses the upgrade for
# everyone who has the file. omarchy-update-system-pkgs-when-conflicted recovers from
# that, but the cheaper answer is to ship the file in the package instead.
#
# This flags a script writing such a path unless a PKGBUILD installs it, or it
# is recorded below with the reason it cannot be packaged.
#
# It is a net, not a proof: it reads the destination off the command, so a path
# assembled from variables passes through. The two known cases are recorded
# below, and a new one is caught only if it names the path where it writes it.

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT" <<'PYTHON'
import os, re, sys
from pathlib import Path

root = Path(sys.argv[1])

# Paths Omarchy writes into /usr that no package owns, with the reason.
allowed = {
  # Symlinks into another package's icon theme; owning them would mean owning
  # paths inside Yaru.
  "/usr/share/icons/Yaru/scalable/actions",
  # Hardware-conditional sleep hooks, installed only on the machines that need
  # them so the hook does not exist where it does not apply.
  "/usr/lib/systemd/system-sleep",
  # Written through a variable, so the scan below cannot see them at the point
  # they are written. Both drop configuration into another project's tree rather
  # than Omarchy's, which is why neither is a candidate for omarchy-settings.
  "/usr/share/chromium/extensions",
  "/usr/lib/firefox/distribution",
  # Static content that belongs in omarchy-settings. It cannot move there in the
  # same release that first ships omarchy-update-system-pkgs-when-conflicted: the
  # upgrade carrying the handler is the one that would hit the conflict, and the
  # handler only helps once it is on disk. Package it the release after.
  "/usr/lib/chromium/initial_preferences",
}

# One-time 3.x upgrade. It runs before this rule existed and cannot be made to
# retroactively matter for machines that already ran it.
skip_scripts = {"bin/omarchy-upgrade-to-quattro"}

pkgs_candidates = [
  root.parent / "omarchy-pkgs/pkgbuilds",
  root.parent.parent / "omarchy-pkgs/pkgbuilds",
  root.parent / "omacom/omarchy-pkgs/pkgbuilds",
  Path.home() / "Work/omacom/omarchy-pkgs/pkgbuilds",
]
override = os.environ.get("OMARCHY_PKGS_PATH")
if override:
  pkgs_candidates = [Path(override) / "pkgbuilds", Path(override)] + pkgs_candidates
pkgs_root = next((p for p in pkgs_candidates if p.exists()), None)
if pkgs_root is None:
  print("not ok - omarchy-pkgs checkout found for package ownership check", file=sys.stderr)
  sys.exit(1)

packaged = "\n".join(p.read_text() for p in pkgs_root.glob("*/PKGBUILD"))

# Commands that put a file somewhere, as opposed to reading one.
# /etc is administrator territory that Omarchy legitimately edits. /usr is
# package territory, where writing anything is the thing worth catching.
writer = re.compile(r"\b(tee|cp|install|ln)\b|>\s*/usr/")
target = re.compile(r"/usr/[A-Za-z0-9._@/+-]+")

problems = []
for base in ("bin", "install", "migrations"):
  for path in sorted((root / base).rglob("*")):
    if not path.is_file():
      continue
    rel = str(path.relative_to(root))
    if rel in skip_scripts:
      continue
    # Join continuations first, so a command split across lines is judged whole
    # rather than as a source path on one line and a destination on the next.
    joined, buf, start = [], "", 1
    for lineno, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
      if not buf:
        start = lineno
      if line.rstrip().endswith("\\"):
        buf += line.rstrip()[:-1] + " "
        continue
      joined.append((start, buf + line))
      buf = ""
    if buf:
      joined.append((start, buf))

    for lineno, line in joined:
      code = line.split("#", 1)[0]
      if not writer.search(code):
        continue
      # A redirection names its destination directly. Otherwise cp/install/ln
      # put the destination last, and anything earlier is a source being read.
      redirect = re.search(r">\s*\"?(/usr/[^\s\"]+)", code)
      if redirect:
        hit = redirect.group(1).rstrip("/")
      else:
        tokens = re.sub(r"[12]?>\s*\S+", "", code).split()
        if not tokens or not tokens[-1].startswith("/usr/"):
          continue
        hit = tokens[-1].rstrip("/")
      # Omarchy's own tree and its binaries are covered elsewhere.
      if hit.startswith(("/usr/share/omarchy", "/usr/bin")) or hit.count("/") < 3:
        continue
      # Directory or file form of a recorded path both count as recorded, but
      # only on a path boundary: system-sleeping is not system-sleep.
      def covers(a, b):
        return a == b or b.startswith(a + "/")
      if any(covers(a, hit) or covers(hit, a) for a in allowed):
        continue
      # Likewise in the PKGBUILD text, where the path is a destination rather
      # than a prefix of a longer one.
      if re.search(re.escape(hit) + r'(?=["\'\s]|$)', packaged, re.M):
        continue
      problems.append(f"{rel}:{lineno}: {hit}")

if problems:
  print("not ok - Omarchy writes paths under /usr that no package owns", file=sys.stderr)
  for p in problems:
    print(f"  {p}", file=sys.stderr)
  print(
    "\nShip it from a PKGBUILD so pacman owns it, or record it in this test\n"
    "with the reason it cannot be packaged.",
    file=sys.stderr,
  )
  sys.exit(1)
PYTHON

pass "no Omarchy script writes a path under /usr that no package owns"
