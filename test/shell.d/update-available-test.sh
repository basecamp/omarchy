#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
mkdir -p "$stub_bin"

# Captured before the stub shadows it: the plugin checkouts below are real
# repositories, so the stub hands their calls to the real thing.
real_git=$(command -v git)

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES:-updates}" in
  updates)
    printf 'linux 6.1-1 -> 6.1-2\nomarchy 4.0.0-1 -> 4.0.1-1\nomarchy-settings 4.0.0-1 -> 4.0.1-1\nomarchy-dev 4.1.0-1 -> 4.1.1-1\nomarchy-settings-dev 4.1.0-1 -> 4.1.1-1\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
  fail)
    echo "check failed" >&2
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Qq)
    case "${TEST_INSTALLED_PACKAGE:-omarchy}" in
      omarchy)
        [[ $2 == "omarchy" ]]; exit $?
        ;;
      omarchy-dev)
        [[ $2 == "omarchy-dev" ]]; exit $?
        ;;
      both)
        [[ $2 == "omarchy" || $2 == "omarchy-dev" ]]; exit $?
        ;;
      none)
        exit 1
        ;;
    esac
    ;;
esac
exit 0
SH
chmod +x "$stub_bin/pacman"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$TEST_GIT_LOG"

[[ $1 == "-C" ]] || exit 1
dir="$2"
shift 2

# Only the dev checkout is mocked. Plugin checkouts are real repositories in
# the test's temp dir, so their ancestry answers come from git itself.
if [[ $dir != "$OMARCHY_PATH" ]]; then
  exec "$TEST_REAL_GIT" -C "$dir" "$@"
fi

case "$1" in
  fetch)
    [[ ${TEST_GIT_FETCH:-ok} == "ok" ]]
    ;;
  rev-parse)
    case "$2" in
      --is-inside-work-tree)
        [[ ${TEST_GIT_CHECKOUT:-yes} == "yes" ]] || exit 1
        echo true
        ;;
      --abbrev-ref)
        [[ ${TEST_GIT_UPSTREAM:-origin/quattro} != "none" ]] || exit 1
        echo "${TEST_GIT_UPSTREAM:-origin/quattro}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  rev-list)
    echo "${TEST_GIT_BEHIND:-0}"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/git"

run_checker() {
  # HOME is always pointed somewhere controlled: the plugin scan reads
  # ~/.config/omarchy/plugins, and the developer's own plugins must never
  # decide the result of a test.
  OMARCHY_PATH="${TEST_OMARCHY_PATH:-/usr/share/omarchy}" \
    HOME="${TEST_HOME:-$test_tmp/home}" \
    TEST_GIT_LOG="$git_log" \
    TEST_REAL_GIT="$real_git" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-available"
}

capture_checker() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  set +e
  (
    export "$@"
    run_checker
  ) >"$stdout_file" 2>"$stderr_file"
  local status=$?
  set -e
  return "$status"
}

stdout="$test_tmp/stdout"
stderr="$test_tmp/stderr"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy update is available"
grep -q '^omarchy ' "$stdout" || fail "update checker prints omarchy updates"
! grep -q '^omarchy-settings ' "$stdout" || fail "update checker ignores omarchy-settings updates"
! grep -q '^linux ' "$stdout" || fail "update checker ignores non-Omarchy package updates"
! grep -q '^omarchy-dev ' "$stdout" || fail "update checker ignores omarchy-dev when omarchy is installed"
pass "update checker detects installed omarchy package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy-dev; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy-dev update is available"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev updates"
! grep -q '^omarchy-settings-dev ' "$stdout" || fail "update checker ignores omarchy-settings-dev updates"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker detects installed omarchy-dev package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=both; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker prefers omarchy-dev when both packages are installed"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev when both packages are installed"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker prefers omarchy-dev over omarchy"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=none; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no Omarchy package is installed"
[[ ! -s $stderr ]] || fail "update checker is quiet when no Omarchy package is installed"
pass "update checker ignores systems without omarchy or omarchy-dev installed"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=none TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no updates are available"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker prints up-to-date message"
pass "update checker reports up-to-date Omarchy packages"

: >"$git_log"
if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=2; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when dev commits are available"
grep -Fx 'omarchy-dev-checkout 2 new commits on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports available dev commits" "$(cat "$stdout")"
grep -Fx -- "-C $test_tmp/checkout fetch --quiet" "$git_log" >/dev/null ||
  fail "update checker fetches the dev checkout upstream" "$(cat "$git_log")"
pass "update checker detects new commits in the dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when the dev checkout is current"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker reports a current dev checkout"
pass "update checker ignores a current dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=1 \
  TEST_GIT_FETCH=fail; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker uses cached upstream state when fetch fails"
grep -Fx 'omarchy-dev-checkout 1 new commit on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports cached dev commits after a fetch failure" "$(cat "$stdout")"
[[ ! -s $stderr ]] || fail "update checker keeps dev fetch failures quiet" "$(cat "$stderr")"
pass "update checker uses cached dev state when fetching is unavailable"

# ---- git-managed plugins -----------------------------------------------------
#
# Real repositories rather than a mock, so what is asserted is the ancestry
# logic itself: a plugin is only behind when the remote holds a commit this
# checkout does not, whether or not that commit has already been fetched.

plugin_home="$test_tmp/plugin-home"
plugins_dir="$plugin_home/.config/omarchy/plugins"
mkdir -p "$plugins_dir"

git_quiet() {
  "$real_git" -c init.defaultBranch=main -c user.email=test@example.com \
    -c user.name=Test -c commit.gpgsign=false "$@" >/dev/null 2>&1
}

commit_into() {
  local repo="$1" message="$2"
  echo "$message" >>"$repo/log.txt"
  git_quiet -C "$repo" add log.txt
  git_quiet -C "$repo" commit -m "$message"
}

new_plugin() {
  local id="$1"
  local origin="$test_tmp/origins/$id.git"
  local seed="$test_tmp/seeds/$id"

  mkdir -p "$origin" "$seed"
  git_quiet init --bare "$origin"
  git_quiet init "$seed"
  commit_into "$seed" "first"
  git_quiet -C "$seed" remote add origin "$origin"
  git_quiet -C "$seed" push origin main
  git_quiet clone "$origin" "$plugins_dir/$id"
}

# Origin has moved and the new commit has already been fetched — the state a
# user is left in by looking at `omarchy plugin update` and declining it.
new_plugin fetched-behind
commit_into "$test_tmp/seeds/fetched-behind" "second"
git_quiet -C "$test_tmp/seeds/fetched-behind" push origin main
git_quiet -C "$plugins_dir/fetched-behind" fetch origin

# Origin has moved and this checkout has never seen the commit.
new_plugin never-fetched
commit_into "$test_tmp/seeds/never-fetched" "second"
git_quiet -C "$test_tmp/seeds/never-fetched" push origin main

# Current, and one carrying local commits origin does not have.
new_plugin current
new_plugin ahead
commit_into "$plugins_dir/ahead" "local work"

# Neither of these can be behind anything: no checkout, and no remote.
mkdir -p "$plugins_dir/not-a-checkout"
git_quiet init "$plugins_dir/no-remote"
commit_into "$plugins_dir/no-remote" "first"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_HOME="$plugin_home"; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when a plugin is behind" "$(cat "$stdout")"
grep -Fx 'plugin fetched-behind 1 new commit' "$stdout" >/dev/null ||
  fail "update checker counts commits for a plugin that already holds them" "$(cat "$stdout")"
grep -Fx 'plugin never-fetched has an update' "$stdout" >/dev/null ||
  fail "update checker reports a plugin whose new commit is not local yet" "$(cat "$stdout")"
! grep -q '^plugin current ' "$stdout" || fail "update checker reports a current plugin"
! grep -q '^plugin ahead ' "$stdout" || fail "update checker reports a plugin that is ahead of origin"
! grep -q 'not-a-checkout' "$stdout" || fail "update checker inspects a plugin that is not a checkout"
! grep -q 'no-remote' "$stdout" || fail "update checker reports a plugin with no remote"
[[ ! -s $stderr ]] || fail "update checker is quiet while scanning plugins" "$(cat "$stderr")"
pass "update checker detects git-managed plugins that are behind"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero with no plugins installed"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker reports up to date with no plugins"
pass "update checker ignores systems with no plugins installed"

# A plugin update alone must not be silent: the widget only sees the exit code.
if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=omarchy \
  TEST_HOME="$plugin_home"; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker signals an update when only a plugin is behind"
pass "update checker signals the shell widget for plugin-only updates"
