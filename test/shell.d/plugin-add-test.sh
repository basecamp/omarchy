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

cat >"$stub_dir/omarchy-default-agent" <<'STUB'
#!/bin/bash
[[ -n ${OMARCHY_TEST_DEFAULT_AGENT:-} ]] && printf '%s\n' "$OMARCHY_TEST_DEFAULT_AGENT"
STUB

cat >"$stub_dir/omarchy-agent" <<'STUB'
#!/bin/bash
printf '%s\n' "$PWD" >"$OMARCHY_TEST_AGENT_PWD_LOG"
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_ARGS_LOG"
printf '%s' "${3:-}" >"$OMARCHY_TEST_AGENT_PROMPT_LOG"
if [[ ${OMARCHY_TEST_AGENT_MUTATE:-false} == "true" ]]; then
  plugin_dir=$(sed -n '3{s/^  //;p;}' "$OMARCHY_TEST_AGENT_PROMPT_LOG")
  printf '\n// changed by agent\n' >>"$plugin_dir/Widget.qml"
fi
[[ ${OMARCHY_TEST_AGENT_FAIL:-false} != "true" ]]
STUB
chmod +x "$stub_dir/omarchy-shell"
chmod +x "$stub_dir/omarchy-default-agent" "$stub_dir/omarchy-agent"

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

review_incoming="$TMPDIR/review-incoming"
write_plugin "$review_incoming" "acme.review" "Reviewed"
git -C "$review_incoming" init -q
git -C "$review_incoming" add .
git -C "$review_incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

agent_args_log="$TMPDIR/agent-args"
agent_prompt_log="$TMPDIR/agent-prompt"
agent_pwd_log="$TMPDIR/agent-pwd"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-add "$review_incoming" --review --yes 2>&1) &&
  fail "plugin add starts a requested review without a default agent" "$output"
grep -qF -- "--review requires a default agent" <<<"$output" ||
  fail "plugin add explains that a requested review needs a default agent" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.review ]] ||
  fail "plugin add installs before checking for the requested review agent"
pass "plugin add requires a configured default agent for explicit reviews"

HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  OMARCHY_TEST_DEFAULT_AGENT=codex \
  OMARCHY_TEST_AGENT_ARGS_LOG="$agent_args_log" \
  OMARCHY_TEST_AGENT_PROMPT_LOG="$agent_prompt_log" \
  OMARCHY_TEST_AGENT_PWD_LOG="$agent_pwd_log" \
  omarchy-plugin-add "$review_incoming" --review --yes >/dev/null

[[ -d $test_home/.config/omarchy/plugins/acme.review ]] ||
  fail "plugin add does not install after a successful requested review"
[[ $(<"$agent_pwd_log") == "$test_home/.config/omarchy/plugins" ]] ||
  fail "plugin review launches from outside the untrusted repository"
[[ $(tr '\0' ' ' <"$agent_args_log") == "--inline --prompt "* ]] ||
  fail "plugin review invokes the default agent inline with a prompt"
grep -qF "Plugin id: acme.review" "$agent_prompt_log" ||
  fail "plugin review prompt identifies the staged plugin"
grep -qF "Git commit: $(git -C "$review_incoming" rev-parse HEAD)" "$agent_prompt_log" ||
  fail "plugin review prompt pins the reviewed commit"
grep -qF "including AGENTS.md files" "$agent_prompt_log" ||
  fail "plugin review prompt treats repository instructions as untrusted"
pass "plugin add reviews the staged commit before installing it"

failed_incoming="$TMPDIR/failed-incoming"
write_plugin "$failed_incoming" "acme.failed-review" "Failed Review"
git -C "$failed_incoming" init -q
git -C "$failed_incoming" add .
git -C "$failed_incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  OMARCHY_TEST_DEFAULT_AGENT=codex \
  OMARCHY_TEST_AGENT_ARGS_LOG="$agent_args_log" \
  OMARCHY_TEST_AGENT_PROMPT_LOG="$agent_prompt_log" \
  OMARCHY_TEST_AGENT_PWD_LOG="$agent_pwd_log" \
  OMARCHY_TEST_AGENT_FAIL=true \
  omarchy-plugin-add "$failed_incoming" --review --yes 2>&1) &&
  fail "plugin add installs after its agent review fails" "$output"
grep -qF "review with codex failed; plugin was not installed" <<<"$output" ||
  fail "plugin add explains a failed agent review" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.failed-review ]] ||
  fail "plugin add leaves an installed plugin after review failure"
if compgen -G "$test_home/.config/omarchy/plugins/.add.tmp.*" >/dev/null; then
  fail "plugin add leaves a staging directory after review failure"
fi
pass "plugin add cleans up and stops when its agent review fails"

mutated_incoming="$TMPDIR/mutated-incoming"
write_plugin "$mutated_incoming" "acme.mutated-review" "Mutated Review"
git -C "$mutated_incoming" init -q
git -C "$mutated_incoming" add .
git -C "$mutated_incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  OMARCHY_TEST_DEFAULT_AGENT=codex \
  OMARCHY_TEST_AGENT_ARGS_LOG="$agent_args_log" \
  OMARCHY_TEST_AGENT_PROMPT_LOG="$agent_prompt_log" \
  OMARCHY_TEST_AGENT_PWD_LOG="$agent_pwd_log" \
  OMARCHY_TEST_AGENT_MUTATE=true \
  omarchy-plugin-add "$mutated_incoming" --review --yes 2>&1) &&
  fail "plugin add installs a checkout changed by its reviewing agent" "$output"
grep -qF "changed the staged plugin; refusing to install" <<<"$output" ||
  fail "plugin add explains why an agent-modified checkout was rejected" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.mutated-review ]] ||
  fail "plugin add leaves an installed plugin after detecting an agent change"
if compgen -G "$test_home/.config/omarchy/plugins/.add.tmp.*" >/dev/null; then
  fail "plugin add leaves a staging directory after detecting an agent change"
fi
pass "plugin add refuses agent changes to the reviewed checkout"

unreviewed_incoming="$TMPDIR/unreviewed-incoming"
write_plugin "$unreviewed_incoming" "acme.unreviewed" "Unreviewed"
git -C "$unreviewed_incoming" init -q
git -C "$unreviewed_incoming" add .
git -C "$unreviewed_incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"
: >"$agent_args_log"

HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  OMARCHY_TEST_DEFAULT_AGENT=codex \
  OMARCHY_TEST_AGENT_ARGS_LOG="$agent_args_log" \
  OMARCHY_TEST_AGENT_PROMPT_LOG="$agent_prompt_log" \
  OMARCHY_TEST_AGENT_PWD_LOG="$agent_pwd_log" \
  omarchy-plugin-add "$unreviewed_incoming" --yes >/dev/null

[[ ! -s $agent_args_log ]] || fail "--yes unexpectedly opts into an agent review"
[[ -d $test_home/.config/omarchy/plugins/acme.unreviewed ]] ||
  fail "plugin add changes normal --yes installation behavior"
pass "plugin add preserves non-interactive behavior unless review is explicit"
