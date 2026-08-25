#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const store = requireFromRoot('shell/plugins/panels/snippets/SnippetStore.js')

assertEqual(store.blank('   '), true, 'snippets blank treats whitespace as empty')
assertEqual(store.blank('x'), false, 'snippets blank treats non-empty text as non-blank')
assertEqual(store.validName('Docker cleanup'), true, 'snippets validName accepts a real name')
assertEqual(store.validName(''), false, 'snippets validName rejects an empty name')
assertEqual(store.validContent(''), false, 'snippets validContent rejects empty content')

const existing = [
  { id: '1', name: 'Docker cleanup', content: 'docker system prune -af' },
  { id: '2', name: 'Unchanged', content: 'same' }
]

assertEqual(store.duplicateName(existing, 'Unchanged'), true, 'snippets duplicateName detects a collision')
assertEqual(store.duplicateName(existing, 'Unchanged', '2'), false, 'snippets duplicateName excludes the snippet being edited')
assertEqual(store.duplicateName(existing, 'Brand new'), false, 'snippets duplicateName allows a new name')

assertDeepEqual(
  store.displayRows(existing, 'docker'),
  [{ id: '1', name: 'Docker cleanup', preview: 'docker system prune -af' }],
  'snippets displayRows matches by content, not just name'
)
assertDeepEqual(
  store.displayRows(existing, 'unchanged'),
  [{ id: '2', name: 'Unchanged', preview: 'same' }],
  'snippets displayRows search is case-insensitive'
)
assertDeepEqual(store.displayRows(existing, 'nothing matches'), [], 'snippets displayRows returns nothing for no match')

assertEqual(
  store.contentPreview('line one\nline two\t\ttabbed'),
  'line one line two tabbed',
  'snippets contentPreview collapses whitespace onto one line'
)

assertEqual(store.nextUniqueName([], 'Docker cleanup'), 'Docker cleanup (Imported)', 'snippets nextUniqueName suffixes the first collision')
assertEqual(
  store.nextUniqueName(['Docker cleanup (Imported)'], 'Docker cleanup'),
  'Docker cleanup (Imported 2)',
  'snippets nextUniqueName numbers repeated collisions'
)
assertEqual(
  store.nextUniqueName(['Docker cleanup (Imported)', 'Docker cleanup (Imported 2)'], 'Docker cleanup'),
  'Docker cleanup (Imported 3)',
  'snippets nextUniqueName keeps counting past two collisions'
)

const imported = [
  { name: 'Docker cleanup', content: 'docker system prune -af --volumes' },
  { name: 'Unchanged', content: 'same' },
  { name: 'Brand new', content: 'echo hi' }
]
const classified = store.classifyImport(existing, imported)
assertEqual(classified.newCount, 1, 'snippets classifyImport counts genuinely new snippets')
assertDeepEqual(
  classified.conflicts,
  [{ name: 'Docker cleanup', existingContent: 'docker system prune -af', importedContent: 'docker system prune -af --volumes' }],
  'snippets classifyImport reports only differing-content collisions'
)

const dupWithinFile = store.classifyImport([], [
  { name: 'Same', content: 'a' },
  { name: 'Same', content: 'a' }
])
assertEqual(dupWithinFile.newCount, 1, 'snippets classifyImport treats an identical intra-file repeat as one new snippet')
assertEqual(dupWithinFile.conflicts.length, 0, 'snippets classifyImport does not flag an identical intra-file repeat')

const conflictWithinFile = store.classifyImport([], [
  { name: 'Same', content: 'a' },
  { name: 'Same', content: 'b' }
])
assertEqual(conflictWithinFile.newCount, 1, 'snippets classifyImport still counts the first intra-file occurrence as new')
assertEqual(conflictWithinFile.conflicts.length, 1, 'snippets classifyImport flags a differing intra-file repeat as a conflict')
JS

require_command jq
require_command wl-copy

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home/.local/state/omarchy"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
cat >"$WL_COPY_OUT"
SH
chmod +x "$TMPDIR/bin/wl-copy"

export HOME="$TMPDIR/home"
export PATH="$TMPDIR/bin:$PATH"

save() { "$ROOT/bin/omarchy-snippets-save" "$1"; }
delete() { "$ROOT/bin/omarchy-snippets-delete" "$1"; }
copy() { "$ROOT/bin/omarchy-snippets-copy" "$1"; }
snippets_store_path="$HOME/.local/state/omarchy/snippets.json"

# ---- create / update / delete -----------------------------------------

created=$(save '{"id":"","name":"Docker cleanup","content":"docker system prune -af"}')
created_id=$(jq -r '.id' <<<"$created")
[[ -n $created_id ]] || fail "snippets save assigns an id on create"
pass "snippets save assigns an id on create"

[[ $(jq -r --arg id "$created_id" '.snippets[] | select(.id == $id) | .name' "$snippets_store_path") == "Docker cleanup" ]] \
  || fail "snippets save persists the new snippet"
pass "snippets save persists the new snippet"

save '{"id":"","name":"Docker cleanup","content":"different"}' 2>/tmp/snippets-dup-err.$$ && fail "snippets save rejects a duplicate name"
grep -q 'already exists' /tmp/snippets-dup-err.$$ || fail "snippets save reports a plain-language duplicate-name error"
rm -f /tmp/snippets-dup-err.$$
pass "snippets save rejects a duplicate name"

save '{"id":"","name":"","content":"x"}' >/dev/null 2>&1 && fail "snippets save rejects an empty name"
pass "snippets save rejects an empty name"

save '{"id":"","name":"x","content":""}' >/dev/null 2>&1 && fail "snippets save rejects empty content"
pass "snippets save rejects empty content"

save "{\"id\":\"$created_id\",\"name\":\"Docker cleanup\",\"content\":\"docker system prune -af --volumes\"}" >/dev/null
updated_id=$(jq -r --arg name "Docker cleanup" '.snippets[] | select(.name == $name) | .id' "$snippets_store_path")
[[ $updated_id == "$created_id" ]] || fail "snippets save preserves id across an update"
pass "snippets save preserves id across an update"
[[ $(jq -r --arg id "$created_id" '.snippets[] | select(.id == $id) | .content' "$snippets_store_path") == "docker system prune -af --volumes" ]] \
  || fail "snippets save updates content in place"
pass "snippets save updates content in place"

control=$(save '{"id":"","name":"Control","content":"untouched"}')
control_id=$(jq -r '.id' <<<"$control")

delete "$created_id" >/dev/null
[[ $(jq '[.snippets[] | select(.id == "'"$created_id"'")] | length' "$snippets_store_path") == "0" ]] \
  || fail "snippets delete removes the targeted snippet"
pass "snippets delete removes the targeted snippet"
[[ $(jq -r --arg id "$control_id" '.snippets[] | select(.id == $id) | .content' "$snippets_store_path") == "untouched" ]] \
  || fail "snippets delete leaves other snippets untouched"
pass "snippets delete leaves other snippets untouched"

# ---- copy: exact content, no transformation ----------------------------

multiline=$(save "$(jq -cn --arg name "Multiline" --arg content "$(printf 'line one\nline two\ttabbed')" '{id:"",name:$name,content:$content}')")
multiline_id=$(jq -r '.id' <<<"$multiline")
copy_out="$TMPDIR/copied"
WL_COPY_OUT="$copy_out" copy "$multiline_id" >/dev/null
[[ $(<"$copy_out") == "$(printf 'line one\nline two\ttabbed')" ]] || fail "snippets copy sends the exact stored content to wl-copy"
pass "snippets copy sends the exact stored content to wl-copy"

# ---- export / import round trip ----------------------------------------

export_path="$TMPDIR/exported.json"
"$ROOT/bin/omarchy-snippets-export" "$export_path"
jq -e '.version == 1 and (.snippets | all(has("name") and has("content") and (has("id") | not)))' "$export_path" >/dev/null \
  || fail "snippets export strips ids and matches the interchange format"
pass "snippets export strips ids and matches the interchange format"

before_names=$(jq -c '[.snippets[].name] | sort' "$snippets_store_path")
"$ROOT/bin/omarchy-snippets-delete" "$control_id" >/dev/null
"$ROOT/bin/omarchy-snippets-delete" "$multiline_id" >/dev/null
preview=$("$ROOT/bin/omarchy-snippets-import-preview" "$export_path")
[[ $(jq -r '.newCount' <<<"$preview") == "2" ]] || fail "snippets import-preview reports every snippet as new against an emptied store"
pass "snippets import-preview reports every snippet as new against an emptied store"
"$ROOT/bin/omarchy-snippets-import-apply" "$export_path" '[]' >/dev/null
after_names=$(jq -c '[.snippets[].name] | sort' "$snippets_store_path")
[[ $before_names == "$after_names" ]] || fail "snippets export/import round trip restores the same names"
pass "snippets export/import round trip restores the same names"

# ---- import conflict resolution ----------------------------------------

save '{"id":"","name":"Docker cleanup","content":"docker system prune -af"}' >/dev/null
jq -n '{version:1, snippets:[{name:"Docker cleanup", content:"docker system prune -af --volumes --force"}]}' >"$TMPDIR/conflict.json"
conflict_preview=$("$ROOT/bin/omarchy-snippets-import-preview" "$TMPDIR/conflict.json")
[[ $(jq -r '.conflicts | length' <<<"$conflict_preview") == "1" ]] || fail "snippets import-preview reports a differing-content conflict"
pass "snippets import-preview reports a differing-content conflict"

"$ROOT/bin/omarchy-snippets-import-apply" "$TMPDIR/conflict.json" '[{"name":"Docker cleanup","action":"keep-both"}]' >/dev/null
jq -e '[.snippets[] | select(.name == "Docker cleanup (Imported)")] | length == 1' "$snippets_store_path" >/dev/null \
  || fail "snippets import keep-both adds a deterministically suffixed snippet"
pass "snippets import keep-both adds a deterministically suffixed snippet"
jq -e '[.snippets[] | select(.name == "Docker cleanup")] | length == 1' "$snippets_store_path" >/dev/null \
  || fail "snippets import keep-both leaves the original snippet untouched"
pass "snippets import keep-both leaves the original snippet untouched"

# ---- invalid import leaves the store untouched --------------------------

before_hash=$(sha256sum "$snippets_store_path")
echo "not json" >"$TMPDIR/bad.json"
"$ROOT/bin/omarchy-snippets-import-preview" "$TMPDIR/bad.json" >/dev/null 2>&1 && fail "snippets import-preview rejects invalid JSON"
"$ROOT/bin/omarchy-snippets-import-apply" "$TMPDIR/bad.json" '[]' >/dev/null 2>&1 && fail "snippets import-apply rejects invalid JSON"
after_hash=$(sha256sum "$snippets_store_path")
[[ $before_hash == "$after_hash" ]] || fail "snippets store is byte-identical after a rejected import"
pass "snippets store is byte-identical after a rejected import"

echo '{"version":2,"snippets":[]}' >"$TMPDIR/badversion.json"
"$ROOT/bin/omarchy-snippets-import-preview" "$TMPDIR/badversion.json" 2>/tmp/snippets-ver-err.$$ && fail "snippets import-preview rejects an unsupported version"
grep -q 'Unsupported snippet format version' /tmp/snippets-ver-err.$$ || fail "snippets import-preview names the unsupported-version error"
rm -f /tmp/snippets-ver-err.$$
pass "snippets import-preview rejects an unsupported version"

# ---- large import completes as one write --------------------------------

node -e '
const items = []
for (let i = 0; i < 1500; i++) items.push({ name: "bulk " + i, content: "content " + i })
console.log(JSON.stringify({ version: 1, snippets: items }))
' >"$TMPDIR/large.json"
"$ROOT/bin/omarchy-snippets-import-apply" "$TMPDIR/large.json" '[]' >/dev/null
[[ $(jq '[.snippets[] | select(.name | startswith("bulk "))] | length' "$snippets_store_path") == "1500" ]] \
  || fail "snippets import-apply completes a 1500-snippet import as one write"
pass "snippets import-apply completes a 1500-snippet import as one write"

# ---- storage permissions -------------------------------------------------

perm=$(stat -c %a "$snippets_store_path")
[[ $perm == "600" ]] || fail "snippets store is not readable by other users" "mode: $perm"
pass "snippets store is not readable by other users"

# ---- no network tooling anywhere in the CLI -----------------------------

if grep -lE '\b(curl|wget)\b' "$ROOT"/bin/omarchy-snippets-* >/dev/null 2>&1; then
  fail "snippets CLI scripts do not reference any network tool"
fi
pass "snippets CLI scripts do not reference any network tool"
