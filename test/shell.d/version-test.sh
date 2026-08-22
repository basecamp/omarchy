#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
mkdir -p "$stub_bin"

# The edge channel installs omarchy-dev. Older builds did not declare
# provides=(omarchy), so a query for plain omarchy finds nothing there.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Q" ]] || exit 1
shift
for package in "$@"; do
  case ",${OMARCHY_TEST_PACKAGES:-}," in
    *",$package,"*)
      echo "$package ${OMARCHY_TEST_VERSION:-4.0.0-1}"
      exit 0
      ;;
  esac
done
echo "error: package '$1' was not found" >&2
exit 1
STUB
chmod +x "$stub_bin/pacman"

# Fails the way a non-checkout does, so only the log distinguishes a package-backed
# path that skipped git from one that asked git and got nothing.
cat >"$stub_bin/git" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_GIT_LOG"
exit 1
STUB
chmod +x "$stub_bin/git"

cat >"$stub_bin/readlink" <<'STUB'
#!/bin/bash
if [[ -n ${OMARCHY_TEST_RESOLVED_PATH:-} ]]; then
  echo "$OMARCHY_TEST_RESOLVED_PATH"
else
  command -p readlink "$@"
fi
STUB
chmod +x "$stub_bin/readlink"

version() {
  OMARCHY_TEST_PACKAGES="$1" \
    OMARCHY_PATH="${2:-/usr/share/omarchy}" \
    TEST_GIT_LOG="$git_log" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-version"
}

[[ $(version omarchy) == "4.0.0-1" ]] || fail "version reports the stable package"
pass "version reports the stable package"

[[ $(version omarchy-dev) == "4.0.0-1" ]] || fail "version reports the edge package"
pass "version reports the edge package"

[[ $(OMARCHY_TEST_RESOLVED_PATH=/usr/share/omarchy version omarchy "$test_tmp/legacy-omarchy-link") == "4.0.0-1" ]] ||
  fail "version recognizes the legacy Omarchy path symlink"
: >"$git_log"
if OMARCHY_TEST_RESOLVED_PATH=/usr/share/omarchy OMARCHY_PATH="$test_tmp/legacy-omarchy-link" \
  TEST_GIT_LOG="$git_log" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-version-branch" >/dev/null 2>&1; then
  fail "version branch rejects the legacy Omarchy path symlink"
fi
[[ ! -s $git_log ]] ||
  fail "version branch does not inspect the legacy Omarchy path symlink as git" "$(cat "$git_log")"
pass "version commands recognize the legacy Omarchy path symlink"

# A checkout reports its hash instead, so packages are irrelevant there.
[[ $(version "" "$test_tmp/checkout") == "dev" ]] || fail "version reports a dev checkout"
pass "version reports a dev checkout"

if version "" >/dev/null 2>&1; then
  fail "version fails when no Omarchy package is installed"
fi
pass "version fails when no Omarchy package is installed"

# The snapshot description is only a label, so a failed lookup must not abort
# the update under set -e.
snapshot_desc=$(
  set -e
  PATH="$stub_bin:$PATH" OMARCHY_TEST_PACKAGES="" OMARCHY_PATH=/usr/share/omarchy \
    bash -c 'DESC="$(omarchy-version 2>/dev/null || echo unknown)"; echo "$DESC"' 2>/dev/null
) || fail "snapshot survives an unknown version"

[[ $snapshot_desc == "unknown" ]] || fail "snapshot labels an unknown version" "actual: $snapshot_desc"
pass "snapshot survives an unknown version"
