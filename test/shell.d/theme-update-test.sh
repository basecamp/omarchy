#!/bin/bash

set -euo pipefail

# shellcheck source=test/shell.d/base-test.sh
source "$(dirname "$0")/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git_quiet() {
  git "$@" >/dev/null 2>&1
}

create_theme() {
  local fixture=$1
  local name=${2:-demo}
  local remote="$fixture/remote.git"
  local seed="$fixture/seed"
  local themes="$fixture/home/.config/omarchy/themes"

  mkdir -p "$themes" "$fixture/home/.local/state/omarchy/current" "$fixture/home/.cache/omarchy"
  git_quiet init --bare "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  git_quiet init -b main "$seed"
  git -C "$seed" config user.email test@example.com
  git -C "$seed" config user.name Test
  printf 'initial\n' >"$seed/colors.toml"
  git_quiet -C "$seed" add colors.toml
  git_quiet -C "$seed" commit -m initial
  git_quiet -C "$seed" remote add origin "$remote"
  git_quiet -C "$seed" push -u origin main
  git_quiet clone "$remote" "$themes/$name"
  git -C "$themes/$name" config user.email test@example.com
  git -C "$themes/$name" config user.name Test
  printf '%s\n' "$name" >"$fixture/home/.local/state/omarchy/current/theme.name"
}

commit_remote() {
  local fixture=$1
  local path=$2
  local content=$3

  mkdir -p "$(dirname "$fixture/seed/$path")"
  printf '%s\n' "$content" >"$fixture/seed/$path"
  git_quiet -C "$fixture/seed" add -A
  git_quiet -C "$fixture/seed" commit -m "$content"
  git_quiet -C "$fixture/seed" push origin main
  git -C "$fixture/seed" rev-parse HEAD
}

run_check() {
  local fixture=$1

  HOME="$fixture/home" \
    PATH="$ROOT/bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_THEME_UPDATE_DIR="$fixture/home/.config/omarchy/themes" \
    OMARCHY_THEME_UPDATE_STATE="$fixture/state.json" \
    OMARCHY_THEME_UPDATE_LOCK="$fixture/update.lock" \
    OMARCHY_THEME_CURRENT_FILE="$fixture/home/.local/state/omarchy/current/theme.name" \
    OMARCHY_THEME_NETWORK_TIMEOUT=3 \
    OMARCHY_THEME_FETCH_TIMEOUT=5 \
    OMARCHY_THEME_CHECK_BUDGET=20 \
    "$ROOT/bin/omarchy-theme-update-status"
}

run_apply() {
  local fixture=$1
  shift

  HOME="$fixture/home" \
    PATH="$ROOT/bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_THEME_UPDATE_DIR="$fixture/home/.config/omarchy/themes" \
    OMARCHY_THEME_UPDATE_STATE="$fixture/state.json" \
    OMARCHY_THEME_UPDATE_LOCK="$fixture/update.lock" \
    OMARCHY_THEME_CURRENT_FILE="$fixture/home/.local/state/omarchy/current/theme.name" \
    OMARCHY_THEME_NETWORK_TIMEOUT=3 \
    OMARCHY_THEME_FETCH_TIMEOUT=5 \
    OMARCHY_THEME_CHECK_BUDGET=20 \
    "$ROOT/bin/omarchy-theme-update" "$@"
}

fixture="$work/pinned"
create_theme "$fixture"
target_a=$(commit_remote "$fixture" colors.toml target-a)
run_check "$fixture" >"$fixture/check.json"
jq -e --arg target "$target_a" '
  .outdated == 1 and .actionable == 1 and .blocked == 0 and .review == 0 and
  .themes[0].state == "update" and .themes[0].current == true and
  .themes[0].targetCommit == $target
' "$fixture/check.json" >/dev/null
target_b=$(commit_remote "$fixture" colors.toml target-b)
run_apply "$fixture" demo "$target_a" >"$fixture/apply.out"
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$target_a" ]] || fail "theme apply installs the reviewed commit"
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) != "$target_b" ]] || fail "theme apply ignores a newer moving remote target"
pass "theme apply remains pinned when the remote advances"

fixture="$work/remote-rewrite"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml reviewed)
run_check "$fixture" >/dev/null
base=$(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD)
git_quiet -C "$fixture/seed" checkout --orphan rewritten
git_quiet -C "$fixture/seed" rm -rf .
printf 'rewritten\n' >"$fixture/seed/colors.toml"
git_quiet -C "$fixture/seed" add colors.toml
git_quiet -C "$fixture/seed" commit -m rewritten
git_quiet -C "$fixture/seed" push --force origin HEAD:main
if run_apply "$fixture" demo "$target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply accepts a reviewed target after the upstream branch was rewritten"
fi
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$base" ]] || fail "remote rewrite leaves the theme unchanged"
pass "theme apply rejects a reviewed target removed from its upstream"

fixture="$work/target-mismatch"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml reviewed)
run_check "$fixture" >/dev/null
base=$(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD)
replacement=0
[[ ${target: -1} == 0 ]] && replacement=1
manipulated_target="${target%?}${replacement}"
if run_apply "$fixture" demo "$manipulated_target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply rejects a target that differs from the review"
fi
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$base" ]] || fail "target mismatch leaves the theme unchanged"
pass "theme apply rejects manipulated target commits before mutation"

fixture="$work/tracked-edits"
create_theme "$fixture"
commit_remote "$fixture" colors.toml remote >/dev/null
printf 'local\n' >"$fixture/home/.config/omarchy/themes/demo/colors.toml"
run_check "$fixture" >"$fixture/check.json"
jq -e '.themes[0].state == "local-edits" and .themes[0].reason == "tracked-edits" and .blocked == 1 and .review == 1' "$fixture/check.json" >/dev/null
pass "theme check blocks tracked local edits"

fixture="$work/prefix-collision"
create_theme "$fixture"
printf 'local file\n' >"$fixture/home/.config/omarchy/themes/demo/assets"
commit_remote "$fixture" assets/icon.svg remote-icon >/dev/null
run_check "$fixture" >"$fixture/check.json"
jq -e '.themes[0].state == "local-edits" and .themes[0].reason == "untracked-conflict"' "$fixture/check.json" >/dev/null
pass "theme check catches untracked file-to-directory prefix collisions"

fixture="$work/reverse-prefix-collision"
create_theme "$fixture"
mkdir -p "$fixture/home/.config/omarchy/themes/demo/assets"
printf 'local file\n' >"$fixture/home/.config/omarchy/themes/demo/assets/icon.svg"
commit_remote "$fixture" assets remote-file >/dev/null
run_check "$fixture" >"$fixture/check.json"
jq -e '.themes[0].state == "local-edits" and .themes[0].reason == "untracked-conflict"' "$fixture/check.json" >/dev/null
pass "theme check catches untracked directory-to-file prefix collisions"

fixture="$work/collision-after-check"
create_theme "$fixture"
target=$(commit_remote "$fixture" assets/icon.svg remote-icon)
run_check "$fixture" >/dev/null
base=$(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD)
printf 'local file\n' >"$fixture/home/.config/omarchy/themes/demo/assets"
if run_apply "$fixture" demo "$target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply accepts an untracked collision introduced after the check"
fi
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$base" ]] || fail "late untracked collision leaves the theme unchanged"
[[ $(<"$fixture/home/.config/omarchy/themes/demo/assets") == "local file" ]] || fail "late untracked collision preserves local content"
pass "theme apply rechecks untracked collisions immediately before mutation"

fixture="$work/tracked-edit-after-check"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml remote)
run_check "$fixture" >/dev/null
base=$(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD)
printf 'late local edit\n' >"$fixture/home/.config/omarchy/themes/demo/colors.toml"
if run_apply "$fixture" demo "$target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply accepts tracked edits introduced after the check"
fi
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$base" ]] || fail "late tracked edit leaves the theme unchanged"
[[ $(<"$fixture/home/.config/omarchy/themes/demo/colors.toml") == "late local edit" ]] || fail "late tracked edit preserves local content"
pass "theme apply rechecks tracked edits immediately before mutation"

fixture="$work/unreachable"
create_theme "$fixture"
git -C "$fixture/home/.config/omarchy/themes/demo" remote set-url origin "$fixture/missing.git"
run_check "$fixture" >"$fixture/check.json"
jq -e '.themes[0].state == "unreachable" and .themes[0].reason == "remote-unreachable" and .actionable == 0' "$fixture/check.json" >/dev/null
pass "theme check reports an unreachable remote without actionable state"

fixture="$work/provenance"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml remote >/dev/null && git -C "$fixture/seed" rev-parse HEAD)
run_check "$fixture" >/dev/null
other_remote="$fixture/other.git"
git_quiet init --bare "$other_remote"
git -C "$fixture/home/.config/omarchy/themes/demo" remote set-url origin "$other_remote"
if run_apply "$fixture" demo "$target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply rejects changed remote provenance"
fi
grep -q 'remote URL changed' "$fixture/apply.err" || fail "theme apply explains changed remote provenance"
pass "theme apply rejects changed remote provenance before fetch"

fixture="$work/executable-config"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml remote)
run_check "$fixture" >/dev/null
marker="$fixture/filter-ran"
git -C "$fixture/home/.config/omarchy/themes/demo" config filter.evil.clean "touch $marker"
if run_apply "$fixture" demo "$target" >"$fixture/apply.out" 2>"$fixture/apply.err"; then
  fail "theme apply rejects executable repository Git filters"
fi
[[ ! -e $marker ]] || fail "theme apply executed repository Git filter configuration"
run_check "$fixture" >"$fixture/check.json"
jq -e '.themes[0].state == "invalid" and .themes[0].reason == "executable-git-filter"' "$fixture/check.json" >/dev/null
[[ ! -e $marker ]] || fail "theme check executed repository Git filter configuration"
pass "theme check and apply reject executable repository Git filters"

fixture="$work/remove"
create_theme "$fixture" active
mkdir -p "$fixture/home/.config/omarchy/themes/removable"
stub_bin="$fixture/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-notification-send"

if HOME="$fixture/home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-theme-remove" active >"$fixture/remove.out" 2>"$fixture/remove.err"; then
  fail "theme remove refuses the active theme"
fi
[[ -d $fixture/home/.config/omarchy/themes/active ]] || fail "active theme remains installed"
HOME="$fixture/home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-theme-remove" removable >/dev/null
[[ ! -e $fixture/home/.config/omarchy/themes/removable ]] || fail "inactive theme was not removed"
if HOME="$fixture/home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-theme-remove" ../active >/dev/null 2>&1; then
  fail "theme remove accepts path traversal"
fi
pass "theme removal is path-confined and protects the active theme"

fixture="$work/cli-compat"
create_theme "$fixture"
target=$(commit_remote "$fixture" colors.toml current)
run_apply "$fixture" >/dev/null
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$target" ]] || fail "no-argument theme update applies a freshly reviewed target"
pass "no-argument theme update preserves the existing update-all command flow"

permissions=$(stat -c '%a' "$fixture/state.json")
(( 10#$permissions <= 600 )) || fail "theme update state permissions are private"
pass "theme update state is written atomically with private permissions"

state_hash=$(sha256sum "$fixture/state.json" | awk '{print $1}')
exec 8>"$fixture/update.lock"
flock -n 8 || fail "test acquires the shared theme update lock"
if run_check "$fixture" >"$fixture/locked-check.out" 2>"$fixture/locked-check.err"; then
  fail "theme check runs while the shared update lock is held"
fi
if run_apply "$fixture" demo "$target" >"$fixture/locked-apply.out" 2>"$fixture/locked-apply.err"; then
  fail "theme apply runs while the shared update lock is held"
fi
[[ $(sha256sum "$fixture/state.json" | awk '{print $1}') == "$state_hash" ]] || fail "locked theme check leaves state unchanged"
[[ $(git -C "$fixture/home/.config/omarchy/themes/demo" rev-parse HEAD) == "$target" ]] || fail "locked theme apply leaves the repository unchanged"
flock -u 8
exec 8>&-
pass "theme check and apply share a non-overlapping state lock"
