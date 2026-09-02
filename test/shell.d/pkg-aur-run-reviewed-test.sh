#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
printf 'args\t%s\n' "$*" >"$REVIEW_LOG"
printf 'pager\t%s\n' "${PAGER:-}" >>"$REVIEW_LOG"
printf 'git-pager\t%s\n' "${GIT_PAGER:-}" >>"$REVIEW_LOG"
STUB
chmod +x "$stub_bin/yay"

REVIEW_LOG="$test_tmp/review" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_UPDATE_LOGGED=1 OMARCHY_UPDATE_CALLER_TTY0=1 OMARCHY_UPDATE_CALLER_TTY1=1 \
  "$ROOT/bin/omarchy-pkg-aur-run-reviewed" -S -- example

args=$(grep $'^args\t' "$test_tmp/review")
reviewer="$ROOT/bin/omarchy-pkg-aur-review"
[[ $args == *"--aur --confirm"* ]] || fail "the shared AUR runner does not enforce AUR-only confirmation"
(( $(grep -o -- '--aur' <<<"$args" | wc -l) == 1 )) || fail "the shared AUR runner duplicates its AUR-only policy"
(( $(grep -o -- '--confirm' <<<"$args" | wc -l) == 1 )) || fail "the shared AUR runner duplicates its confirmation policy"
[[ $args == *"--diffmenu --answerdiff All"* ]] || fail "the shared AUR runner does not request every diff"
[[ $args == *"--editmenu --answeredit All --editor $reviewer"* ]] ||
  fail "the shared AUR runner does not request complete recipe review"
[[ $args == *"-- example"* ]] || fail "the shared AUR runner does not separate targets from options"
grep -Fx $'pager\t'"$reviewer" "$test_tmp/review" >/dev/null || fail "yay's pager bypasses Omarchy review"
grep -Fx $'git-pager\t'"$reviewer" "$test_tmp/review" >/dev/null || fail "git's diff pager bypasses Omarchy review"
pass "one shared runner owns complete recipe and diff review policy"

if "$ROOT/bin/omarchy-pkg-aur-run-reviewed" -S example >/dev/null 2>&1; then
  fail "the shared AUR runner accepts targets without an option separator"
fi
pass "the shared AUR runner requires an explicit target boundary"

grep -q '^unset LESS$' "$ROOT/bin/omarchy-pkg-aur-review" ||
  fail "the blocking recipe pager accepts user flags that can make it auto-exit"
grep -q '^  exec /usr/bin/less -R -+F -+E -+e -- "\$@"$' "$ROOT/bin/omarchy-pkg-aur-review" ||
  fail "the recipe reviewer does not page full files"
grep -q '^  exec /usr/bin/less -R -+F -+E -+e$' "$ROOT/bin/omarchy-pkg-aur-review" ||
  fail "the recipe reviewer does not page streamed diffs"
pass "the review pager owns both file and streamed review without detaching"

if rg -n -- '--answerdiff|--answeredit|--editor' \
  "$ROOT/bin/omarchy-pkg-aur-add" "$ROOT/bin/omarchy-update-aur-pkgs" >"$test_tmp/duplicated-policy"; then
  fail "AUR callers duplicate the shared review flag policy" "$(<"$test_tmp/duplicated-policy")"
fi
pass "AUR callers cannot drift into separate review flag sets"
