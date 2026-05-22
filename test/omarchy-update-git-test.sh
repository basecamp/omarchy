#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMPDIR=""

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Test: stable channel checks out the latest non-pre-release GitHub release, not master tip
#
# Fetches the real latest stable tag from GitHub, builds a local git repo with
# that tag plus a fake pre-release commit on master, and verifies the script
# lands on the stable tag rather than the master tip.

TMPDIR=$(mktemp -d)

latest_tag=$(gh release list --repo basecamp/omarchy --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName')

UPSTREAM="$TMPDIR/upstream"
git init --bare "$UPSTREAM" -q

SEED="$TMPDIR/seed"
git init "$SEED" -q
git -C "$SEED" remote add origin "file://$UPSTREAM"
git -C "$SEED" commit --allow-empty -m "$latest_tag" -q
git -C "$SEED" tag "$latest_tag"
git -C "$SEED" commit --allow-empty -m "pre-release on master" -q
git -C "$SEED" tag v99.0.0alpha
git -C "$SEED" push origin HEAD:master --tags -q 2>/dev/null

OMARCHY_PATH="$TMPDIR/omarchy"
git clone "file://$UPSTREAM" "$OMARCHY_PATH" -q
git -C "$OMARCHY_PATH" reset --hard "$latest_tag" -q

STUBS="$TMPDIR/bin"
mkdir -p "$STUBS"
printf '#!/bin/bash\necho stable\n' > "$STUBS/omarchy-version-channel"
printf '#!/bin/bash\n'              > "$STUBS/omarchy-update-time"
printf '#!/bin/bash\n'              > "$STUBS/hyprctl"
chmod +x "$STUBS/"*

OMARCHY_PATH="$OMARCHY_PATH" PATH="$STUBS:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-update-git" 2>/dev/null

checked_out=$(git -C "$OMARCHY_PATH" describe --tags --exact-match HEAD 2>/dev/null || echo "none")

if [[ $checked_out == "$latest_tag" ]]; then
  pass "stable channel checks out latest non-pre-release GitHub release ($latest_tag), skipping pre-release on master"
else
  fail "stable channel checks out latest non-pre-release GitHub release ($latest_tag), skipping pre-release on master (got: $checked_out)"
fi
