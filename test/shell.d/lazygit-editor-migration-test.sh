#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command sha256sum
require_command stat

migration="$ROOT/migrations/1787422694.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
config="$home/.config/lazygit/config.yml"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

set_editor() {
  mkdir -p "$home/.local/state/omarchy/defaults"
  printf '%s\n' "$1" >"$home/.local/state/omarchy/defaults/editor"
}

assert_line() {
  local key="$1" value="$2" indent="${3:-  }"

  grep -q "^${indent}${key}: ${value}\$" "$config" ||
    fail "config sets $indent$key: $2" "$(cat "$config")"
  pass "config sets $indent$key: $2"
}

# A user config that nests keys sharing names with the ones this migration
# manages; whole-document rewrites would corrupt these.
write_user_config() {
  mkdir -p "$home/.config/lazygit"
  cat >"$config" <<'YAML'
gui:
  showRandomTip: false
keybinding:
  universal:
    edit: v
os:
  suspendOnEdit: true
YAML
}

assert_user_config_intact() {
  grep -q '^gui:' "$config" || fail "keeps unrelated top-level keys" "$(cat "$config")"
  grep -q '^    edit: v$' "$config" || fail "keeps the nested keybinding edit" "$(cat "$config")"
  assert_line suspendOnEdit true
}

# No config at all and no saved editor: defaults to nvim.
run_migration

assert_line editPreset nvim
pass "migration creates the config when it is absent"

# Existing installs ship an empty config file.
mkdir -p "$home/.config/lazygit"
: >"$config"
run_migration

assert_line editPreset nvim
pass "migration fills in an empty config"

# An empty saved editor falls back to nvim instead of aborting.
mkdir -p "$home/.local/state/omarchy/defaults"
: >"$home/.local/state/omarchy/defaults/editor"
run_migration

assert_line editPreset nvim
pass "an empty saved editor falls back to nvim"
rm -f "$home/.local/state/omarchy/defaults/editor"

# An os block without an editPreset gets one; nested and sibling keys survive.
write_user_config
run_migration

assert_line editPreset nvim
assert_user_config_intact
pass "migration inserts into an existing os block"

# A stale preset is replaced without touching the rest of the document.
write_user_config
printf '\n' >>"$config"
sed -i '/^os:/a\  editPreset: vim' "$config"
run_migration

assert_line editPreset nvim
assert_user_config_intact
pass "migration replaces a stale preset"

# Editor mappings.
for pair in \
  "code vscode" \
  "helix helix" \
  "vim vim" \
  "emacs emacs" \
  "zed zed" \
  "zeditor zed" \
  "sublime_text sublime"; do
  read -r editor preset <<<"$pair"
  set_editor "$editor"
  run_migration

  assert_line editPreset "$preset"
done
pass "migration maps every preset editor"

# Cursor has no lazygit preset: an absent choice is seeded with nvim so
# lazygit stops falling back to vim, and the document is left otherwise whole.
set_editor cursor
write_user_config
run_migration

assert_line editPreset nvim
assert_user_config_intact
pass "cursor seeds nvim when no preset is set"

# An explicit choice is kept even when the saved editor has no preset.
set_editor cursor
write_user_config
printf '' >>"$config"
sed -i '/^os:/a\  editPreset: emacs' "$config"
run_migration

assert_line editPreset emacs
assert_user_config_intact
pass "cursor keeps an explicit preset"

# A one-line flow-style os mapping is normalized to block style before a child
# is inserted beneath it, with or without a trailing YAML comment.
set_editor nvim
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
keybinding:
  universal:
    edit: v
os: {suspendOnEdit: true} # tui
YAML
run_migration

assert_line editPreset nvim
assert_line suspendOnEdit true
grep -q '^os: # tui$' "$config" ||
  fail "keeps the trailing comment on the os header" "$(cat "$config")"
grep -q '^os: {' "$config" && fail "rewrites the flow-style os mapping" "$(cat "$config")"
pass "migration rewrites a flow-style os mapping to block style"

# A preset hidden inside a flow mapping is replaced, not duplicated, even when
# the line carries a trailing comment.
set_editor code
cat >"$config" <<'YAML'
os: {editPreset: emacs} # keep this
YAML
run_migration

assert_line editPreset vscode
grep -q '^os: # keep this$' "$config" ||
  fail "keeps the comment on the rewritten header" "$(cat "$config")"
(($(grep -c 'editPreset:' "$config") == 1)) || fail "keeps a single editPreset" "$(cat "$config")"
pass "migration replaces a preset inside a flow-style mapping"

# An inline comment on an existing block-style preset survives the replace,
# including sed metacharacters, and a decoy editPreset in another section is
# neither rewritten nor used as the comment source.
set_editor helix
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
gui:
  editPreset: decoy # gui note
os:
  suspendOnEdit: true
  editPreset: vim # a & b | c \ d
YAML
run_migration

grep -q '^  editPreset: decoy # gui note$' "$config" ||
  fail "leaves another section's editPreset alone" "$(cat "$config")"
grep -qxF "  editPreset: helix # a & b | c \\ d" "$config" ||
  fail "keeps the inline comment when replacing the preset" "$(cat "$config")"
(($(grep -c 'editPreset:' "$config") == 2)) || fail "touches only the os child" "$(cat "$config")"
pass "migration keeps the inline comment when replacing the preset"

# A saved editor without a lazygit preset must not wipe flow members either.
set_editor cursor
cat >"$config" <<'YAML'
os: {editPreset: emacs} # mine
YAML
run_migration

assert_line editPreset emacs
grep -q '^os: # mine$' "$config" ||
  fail "keeps the comment on the untouched flow mapping" "$(cat "$config")"
(($(grep -c 'editPreset:' "$config") == 1)) || fail "keeps the explicit preset" "$(cat "$config")"
pass "cursor keeps an explicit preset inside a flow-style mapping"

# An empty flow mapping still gains a block child.
set_editor code
cat >"$config" <<'YAML'
os: {}
YAML
run_migration

assert_line editPreset vscode
pass "migration handles an empty flow-style os mapping"

# Exotic flow payloads (nested braces) are left untouched instead of being
# rewritten incorrectly.
cat >"$config" <<'YAML'
os: {themeOverride: {light: x}, suspendOnEdit: true}
YAML
run_migration

grep -q '^os: {themeOverride' "$config" ||
  fail "leaves nested-flow mappings untouched" "$(cat "$config")"
if grep -q '  editPreset:' "$config"; then
  fail "does not insert under a nested-flow mapping" "$(cat "$config")"
fi
pass "migration leaves nested-flow mappings untouched"

# Unterminated or bracket-carrying payloads are also left alone.
for payload in '{oops' '{list: [a, b]}'; do
  printf 'os: %s\n' "$payload" >"$config"
  run_migration

  [[ $(cat "$config") == "os: $payload" ]] ||
    fail "leaves os: $payload untouched" "$(cat "$config")"
  if grep -q '  editPreset:' "$config"; then
    fail "does not insert under os: $payload" "$(cat "$config")"
  fi
done
pass "migration leaves malformed and bracketed payloads untouched"

# A private config keeps its mode after normalization, whatever the umask.
set_editor nvim
cat >"$config" <<'YAML'
os: {suspendOnEdit: true}
YAML
chmod 600 "$config"
(umask 000; run_migration)

assert_line suspendOnEdit true
[[ $(stat -c %a "$config") == 600 ]] ||
  fail "normalization preserves the config mode" "$(stat -c %a "$config") $(cat "$config")"
pass "normalization preserves the config mode"

# Four-space configs keep their own indentation for both replace and insert.
set_editor code
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
keybinding:
    universal:
        edit: v
os:
    suspendOnEdit: true
    editPreset: emacs
YAML
run_migration

assert_line editPreset vscode "    "
assert_line suspendOnEdit true "    "
(($(grep -c 'editPreset:' "$config") == 1)) || fail "keeps a single editPreset" "$(cat "$config")"
pass "migration replaces inside a four-space os block"

set_editor nvim
cat >"$config" <<'YAML'
os:
    suspendOnEdit: true
YAML
run_migration

assert_line editPreset nvim "    "
assert_line suspendOnEdit true "    "
pass "migration inserts using a four-space block's indentation"

# An editPreset nested deeper than the os block's children is not the managed
# key; it survives untouched while a fresh child is seeded at the child level.
set_editor cursor
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
os:
  commands:
      editPreset: emacs
YAML
run_migration

assert_line editPreset nvim
assert_line editPreset emacs "      "
pass "deeper-nested editPreset keys are left alone"

# Comments do not participate in indentation: an unindented comment inside the
# os block neither ends it nor hides a later editPreset.
set_editor code
cat >"$config" <<'YAML'
os:
  suspendOnEdit: true
# editor notes
  editPreset: emacs
YAML
run_migration

assert_line editPreset vscode
grep -q '^# editor notes$' "$config" ||
  fail "keeps the unindented comment" "$(cat "$config")"
(($(grep -c 'editPreset:' "$config") == 1)) || fail "keeps a single editPreset" "$(cat "$config")"
pass "unindented comments do not end the os block"

# A leading indented comment does not define the child indentation.
set_editor nvim
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
os:
    # tui notes
    suspendOnEdit: true
YAML
run_migration

assert_line editPreset nvim "    "
grep -q '^    # tui notes$' "$config" ||
  fail "keeps the leading indented comment" "$(cat "$config")"
pass "leading comments do not set the child indentation"

# A null os value carries no settings, so it becomes an empty mapping; a
# trailing comment moves onto the header line.
set_editor nvim
mkdir -p "$home/.config/lazygit"
cat >"$config" <<'YAML'
keybinding:
  universal:
    edit: v
os: null # disabled
YAML
run_migration

assert_line editPreset nvim
grep -q '^os: # disabled$' "$config" ||
  fail "keeps the comment on the normalized null header" "$(cat "$config")"
pass "migration normalizes a null os mapping"

# Every YAML null spelling is supported.
set_editor code
for form in 'null' 'Null' 'NULL' '~'; do
  printf 'os: %s\n' "$form" >"$config"
  run_migration

  assert_line editPreset vscode
done
pass "migration normalizes every null spelling"

# Non-mapping values are not mappings; they stay byte-identical and gain no
# child.
set_editor cursor
for payload in 'true' '42' '"text"' '[a, b]'; do
  printf 'os: %s\n' "$payload" >"$config"
  before=$(sha256sum "$config")
  run_migration

  [[ $before == $(sha256sum "$config") ]] ||
    fail "leaves os: $payload untouched" "$(cat "$config")"
  if grep -q 'editPreset' "$config"; then
    fail "does not insert under os: $payload" "$(cat "$config")"
  fi
done
pass "migration leaves non-mapping os values untouched"

# Idempotence.
before=$(sha256sum "$config")
run_migration
[[ $before == $(sha256sum "$config") ]] || fail "migration is idempotent" "$(cat "$config")"
pass "migration is idempotent"
