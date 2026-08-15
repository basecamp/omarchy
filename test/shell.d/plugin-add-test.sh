#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_plugin() {
  local dir="$1"
  local id="$2"
  local name="$3"

  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "$name",
    "category": "Test",
    "allowMultiple": false
  }
}
JSON
  printf 'import QtQuick\nItem {}\n' >"$dir/Widget.qml"
}

stub_dir="$TMPDIR/stubs"
mkdir -p "$stub_dir"
cat >"$stub_dir/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_dir/omarchy-shell"

test_home="$TMPDIR/home"
write_plugin "$test_home/.config/omarchy/plugins/different-folder" "acme.same" "Installed"

incoming="$TMPDIR/incoming"
write_plugin "$incoming" "acme.same" "Incoming"
git -C "$incoming" init -q
git -C "$incoming" add .
git -C "$incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-add "$incoming" --yes 2>&1) &&
  fail "plugin add accepts an id already installed under another directory" "$output"
grep -qF "plugin id 'acme.same' is already used by" <<<"$output" ||
  fail "plugin add explains the installed id collision" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.same ]] ||
  fail "plugin add leaves a target behind after refusing a duplicate id"
pass "plugin add refuses an installed manifest id regardless of directory name"

# The rest covers the shared security toggle, explicit overrides, and what an
# unfinished or unhappy verdict does to the install.

cat >"$stub_dir/omarchy-default-agent" <<'STUB'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_DEFAULT_AGENT-codex}"
STUB

cat >"$stub_dir/omarchy-toggle-enabled" <<'STUB'
#!/bin/bash
[[ $1 == "agent-security-scan" && ${OMARCHY_TEST_SCANS:-0} == "1" ]]
STUB

# Stands in for the review itself: it records the folder it was pointed at and
# exits with the next code the test has queued, so one scenario can fail a
# review and then pass it.
cat >"$stub_dir/omarchy-plugin-verify" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_VERIFY_LOG"

read -r -a queued <<<"${OMARCHY_TEST_VERIFY_EXITS:-0}"
turn=$(wc -l <"$OMARCHY_TEST_VERIFY_LOG")
(( turn <= ${#queued[@]} )) || turn=${#queued[@]}

exit "${queued[turn - 1]}"
STUB

cat >"$stub_dir/gum" <<'STUB'
#!/bin/bash
kind="$1"
shift

case "$kind" in
choose)
  printf '%s\n' "$*" >>"$OMARCHY_TEST_CHOOSE_LOG"
  turn=$(wc -l <"$OMARCHY_TEST_CHOOSE_LOG")
  mapfile -t answers <"$OMARCHY_TEST_CHOOSE_ANSWERS"
  # Out of queued answers is how this stub escapes out of a picker.
  (( turn <= ${#answers[@]} )) || exit 1
  printf '%s\n' "${answers[turn - 1]}"
  ;;
confirm)
  printf '%s\n' "$*" >>"$OMARCHY_TEST_CONFIRM_LOG"
  # Enabling is another command's job, and another test's subject.
  [[ $* != *Enable* ]] || exit 1
  [[ ${OMARCHY_TEST_CONFIRM:-yes} == "yes" ]]
  ;;
*)
  exit 0
  ;;
esac
STUB

chmod +x "$stub_dir"/*

add_home="$TMPDIR/add-home"
verify_log="$TMPDIR/verify-log"
choose_log="$TMPDIR/choose-log"
choose_answers="$TMPDIR/choose-answers"
confirm_log="$TMPDIR/confirm-log"

export OMARCHY_PATH="$ROOT"
export PATH="$stub_dir:$ROOT/bin:$PATH"
export OMARCHY_TEST_VERIFY_LOG="$verify_log"
export OMARCHY_TEST_CHOOSE_LOG="$choose_log"
export OMARCHY_TEST_CHOOSE_ANSWERS="$choose_answers"
export OMARCHY_TEST_CONFIRM_LOG="$confirm_log"

source_repo="$TMPDIR/source"
write_plugin "$source_repo" "acme.weather" "Weather"
git -C "$source_repo" init -q
git -C "$source_repo" add .
git -C "$source_repo" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

# Every scenario starts from a machine that has never added this plugin, and
# from an empty answer queue.
reset_add() {
  rm -rf "$add_home"
  mkdir -p "$add_home"
  : >"$verify_log"
  : >"$choose_log"
  : >"$choose_answers"
  : >"$confirm_log"
  unset OMARCHY_TEST_VERIFY_EXITS OMARCHY_TEST_DEFAULT_AGENT OMARCHY_TEST_CONFIRM OMARCHY_TEST_SCANS
}

run_add() {
  set +e
  HOME="$add_home" omarchy-plugin-add "$source_repo" "$@" >"$TMPDIR/add-output" 2>&1
  add_status=$?
  set -e
  add_output=$(<"$TMPDIR/add-output")
}

# A terminal is what turns the review into a question rather than a default, so
# the answered scenarios have to run under one.
cat >"$TMPDIR/add-driver" <<'DRIVER'
#!/bin/bash
HOME="$ADD_HOME" omarchy-plugin-add "$@"
DRIVER

run_add_answering() {
  local arguments
  arguments=$(printf '%q ' "$source_repo" "$@")

  set +e
  ADD_HOME="$add_home" script -qec "bash '$TMPDIR/add-driver' $arguments" /dev/null \
    >"$TMPDIR/add-output" 2>&1
  add_status=$?
  set -e
  add_output=$(tr -d '\r' <"$TMPDIR/add-output")
}

added_plugin="$add_home/.config/omarchy/plugins/acme.weather"

reset_add
run_add --yes
(( add_status == 0 )) || fail "plugin add still adds without a review" "$add_output"
[[ -d $added_plugin ]] || fail "plugin add installs the plugin it cloned" "$add_output"
[[ ! -s $verify_log ]] || fail "plugin add reviews nothing unless asked" "$(<"$verify_log")"
[[ ! -s $choose_log ]] || fail "plugin add asks nothing when nobody is watching" "$(<"$choose_log")"
pass "plugin add leaves an unattended install alone"

reset_add
run_add --verify-with-agent --yes
(( add_status == 0 )) || fail "plugin add installs a cleared plugin" "$add_output"
[[ -d $added_plugin ]] || fail "plugin add installs a cleared plugin" "$add_output"
[[ $(wc -l <"$verify_log") == 1 ]] || fail "plugin add reviews once" "$(<"$verify_log")"
# The staged clone, not the installed folder: nothing the agent read gets
# installed unless the install survives its verdict.
grep -qF "$add_home/.config/omarchy/plugins/.add.tmp." "$verify_log" ||
  fail "plugin add reviews the staged clone" "$(<"$verify_log")"
grep -qF -- "--revision" "$verify_log" ||
  fail "plugin add does not bind the review to the staged commit" "$(<"$verify_log")"
pass "plugin add installs what the agent cleared"

reset_add
OMARCHY_TEST_VERIFY_EXITS=1 run_add --verify-with-agent --yes
(( add_status != 0 )) || fail "plugin add installs a plugin the agent refused" "$add_output"
[[ ! -e $added_plugin ]] || fail "plugin add installs a plugin the agent refused" "$add_output"
compgen -G "$add_home/.config/omarchy/plugins/.add.tmp.*" >/dev/null &&
  fail "plugin add leaves the staged clone behind after a refused review"
pass "plugin add refuses what the agent refused"

reset_add
OMARCHY_TEST_VERIFY_EXITS=2 run_add --verify-with-agent --yes
(( add_status != 0 )) || fail "plugin add installs after an unfinished review" "$add_output"
[[ ! -e $added_plugin ]] || fail "plugin add installs after an unfinished review" "$add_output"
pass "plugin add stops when an unattended review never finished"

# A review method of one's own is reason enough to want the review.
reset_add
run_add --skill /etc/omarchy-review.md --yes
(( add_status == 0 )) || fail "a skill of your own adds the plugin" "$add_output"
grep -qF -- "--skill /etc/omarchy-review.md" "$verify_log" ||
  fail "plugin add reviews with the skill it was given" "$(<"$verify_log")"
pass "plugin add asks for the review when a skill comes with it"

reset_add
run_add --skill /etc/omarchy-review.md --no-verify-with-agent --yes
(( add_status == 0 )) || fail "a refused review adds the plugin" "$add_output"
[[ ! -s $verify_log ]] || fail "a skill overrides a refused review" "$(<"$verify_log")"
pass "an explicit no outranks the skill that came with it"

# A review that could not be run at all is not a verdict either: 127 is the
# verifier missing, and nothing about the plugin follows from it.
reset_add
OMARCHY_TEST_VERIFY_EXITS=127 run_add --verify-with-agent --yes
(( add_status != 0 )) || fail "plugin add installs after a review that could not run" "$add_output"
[[ ! -e $added_plugin ]] || fail "plugin add installs after a review that could not run" "$add_output"
pass "plugin add stops on a review it could not run"

reset_add
OMARCHY_TEST_DEFAULT_AGENT="" run_add --verify-with-agent --yes
(( add_status != 0 )) || fail "plugin add verifies without a default agent" "$add_output"
grep -qF "no default coding agent to verify with" <<<"$add_output" ||
  fail "plugin add says how to choose a default agent" "$add_output"
[[ ! -e $added_plugin ]] || fail "plugin add clones before finding it cannot review" "$add_output"
pass "plugin add refuses --verify-with-agent without a default agent"

reset_add
OMARCHY_TEST_SCANS=1 run_add --yes
(( add_status == 0 )) || fail "the shared toggle adds a cleared plugin" "$add_output"
[[ $(wc -l <"$verify_log") == 1 ]] ||
  fail "the shared toggle automatically reviews plugin installs" "$(<"$verify_log")"
[[ ! -s $choose_log ]] || fail "the shared toggle needs no per-plugin preference question" "$(<"$choose_log")"
pass "plugin add follows the shared agent security toggle"

reset_add
OMARCHY_TEST_SCANS=1 run_add --no-verify-with-agent --yes
(( add_status == 0 )) || fail "--no-verify-with-agent adds the plugin" "$add_output"
[[ ! -s $verify_log ]] || fail "--no-verify-with-agent overrides the shared toggle" "$(<"$verify_log")"
pass "an explicit no outranks the shared toggle"

reset_add
OMARCHY_TEST_SCANS=1 OMARCHY_TEST_DEFAULT_AGENT="" run_add --yes
(( add_status == 0 )) || fail "plugin add works when the enabled toggle has no selected agent" "$add_output"
[[ ! -s $verify_log ]] || fail "plugin add scans without a selected default agent" "$(<"$verify_log")"
pass "automatic scans require both the toggle and a default agent"

# A review that crashed says nothing about the plugin, so the offer is to run it
# again rather than to decide on what it never reported.
reset_add
printf '%s\n' "Run the review again" >"$choose_answers"
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_VERIFY_EXITS="2 0" run_add_answering
(( add_status == 0 )) || fail "a re-run review can still clear a plugin" "$add_output"
[[ -d $added_plugin ]] || fail "a re-run review can still install a plugin" "$add_output"
[[ $(wc -l <"$verify_log") == 2 ]] || fail "plugin add runs the review again" "$(<"$verify_log")"
grep -qF "The review did not finish" "$choose_log" ||
  fail "plugin add says the review did not finish" "$(<"$choose_log")"
pass "plugin add offers to run an unfinished review again"

reset_add
printf '%s\n' "Run the review again" >"$choose_answers"
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_VERIFY_EXITS="127 0" run_add_answering
(( add_status == 0 )) || fail "a review that could not run can be run again" "$add_output"
[[ $(wc -l <"$verify_log") == 2 ]] ||
  fail "plugin add runs a failed review again" "$(<"$verify_log")"
pass "plugin add offers to run a review that could not run again"

reset_add
printf '%s\n' "Skip the review and add it" >"$choose_answers"
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_VERIFY_EXITS=2 run_add_answering
(( add_status == 0 )) || fail "a skipped review adds the plugin" "$add_output"
[[ -d $added_plugin ]] || fail "a skipped review adds the plugin" "$add_output"
pass "plugin add can skip a review that never finished"

reset_add
printf '%s\n' "Stop the install" >"$choose_answers"
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_VERIFY_EXITS=2 run_add_answering
(( add_status != 0 )) || fail "a stopped install adds nothing" "$add_output"
[[ ! -e $added_plugin ]] || fail "a stopped install adds nothing" "$add_output"
pass "plugin add can stop on a review that never finished"

# A verdict is a decision, not a crash: it is answered with yes or no, not with
# a re-run.
reset_add
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_VERIFY_EXITS=1 run_add_answering
(( add_status == 0 )) || fail "an overridden verdict adds the plugin" "$add_output"
[[ -d $added_plugin ]] || fail "an overridden verdict adds the plugin" "$add_output"
grep -qF "Add it anyway?" "$confirm_log" ||
  fail "plugin add asks before overriding a verdict" "$(<"$confirm_log")"
pass "plugin add can add a plugin the agent refused"

reset_add
export OMARCHY_TEST_SCANS=1
OMARCHY_TEST_CONFIRM=no OMARCHY_TEST_VERIFY_EXITS=1 run_add_answering
(( add_status != 0 )) || fail "an accepted verdict stops the install" "$add_output"
[[ ! -e $added_plugin ]] || fail "an accepted verdict stops the install" "$add_output"
pass "plugin add stops on a verdict nobody overrides"
