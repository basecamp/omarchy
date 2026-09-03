#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

SNIPPETS_STORE="$HOME/.local/state/omarchy/snippets.json"
snippets_backup=$(mktemp)
snippets_existed=0

if [[ -f $SNIPPETS_STORE ]]; then
  cp "$SNIPPETS_STORE" "$snippets_backup"
  snippets_existed=1
fi

restore_snippets() {
  omarchy-shell shell hide omarchy.snippets >/dev/null 2>&1 || true

  if ((snippets_existed)); then
    cp "$snippets_backup" "$SNIPPETS_STORE"
  else
    rm -f "$SNIPPETS_STORE"
  fi

  rm -f "$snippets_backup"
}
trap restore_snippets EXIT

rm -f "$SNIPPETS_STORE"

# ---- bar icon renders leftmost -----------------------------------------

bar_config="$HOME/.config/omarchy/shell.json"
[[ -f $bar_config ]] || bar_config="$ROOT/config/omarchy/shell.json"
jq -e '[.bar.layout.right[].id] | index("omarchy.snippets") != null' "$bar_config" > /dev/null \
  || fail "snippets bar widget is placed in the right section of the shipped bar layout"
pass "snippets bar widget is placed in the right section of the shipped bar layout"
screenshot "success-snippets-bar-icon"

# ---- open shows the empty state, anchored at the bar icon, not centered --

omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel opens" 15 layer_present "omarchy-keyboard-panel"
wait_until "snippets empty state is visible" 15 screen_contains "No snippets yet"
screenshot "success-snippets-empty-state"
omarchy-shell shell hide omarchy.snippets >/dev/null
wait_until "snippets panel closes" 15 layer_absent "omarchy-keyboard-panel"

# ---- create -------------------------------------------------------------

omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel reopens for create" 15 layer_present "omarchy-keyboard-panel"
wtype -k Tab
wtype -k Return
wait_until "snippets create form opens" 15 screen_contains "New Snippet"
screenshot "success-snippets-create-form"
wtype "Docker cleanup"
wtype -k Tab
wtype "docker system prune -af"
wtype -k Tab -k Tab
wtype -k Return
wait_until "snippets create form closes back to the list" 15 screen_contains "Docker cleanup"
screenshot "success-snippets-created"

# ---- search ---------------------------------------------------------

wtype "cleanup"
wait_until "snippets search matches the new snippet" 15 screen_contains "Docker cleanup"
screenshot "success-snippets-search"
wtype -k Escape

# ---- one-click copy: exact content reaches the real clipboard -----------

wtype -k Return
wait_until "snippets copy closes the panel" 15 layer_absent "omarchy-keyboard-panel"
wait_until "snippets copy restores the exact stored content" 15 bash -c \
  '[[ $(wl-paste --no-newline) == "docker system prune -af" ]]'

# ---- edit (F2 edits the selected row; only one row exists here) ---------

omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel reopens for edit" 15 layer_present "omarchy-keyboard-panel"
wtype -k F2
wait_until "snippets edit form opens" 15 screen_contains "Edit Snippet"
screenshot "success-snippets-edit-form"
wtype -k Tab
wtype -k End " --volumes"
wtype -k Tab -k Tab
wtype -k Return
wait_until "snippets edit form closes back to the list" 15 screen_contains "Docker cleanup"

omarchy-shell shell hide omarchy.snippets >/dev/null
wait_until "snippets panel closes after edit" 15 layer_absent "omarchy-keyboard-panel"
omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel reopens to verify the edit" 15 layer_present "omarchy-keyboard-panel"
wtype -k Return
wait_until "snippets edit closes the panel on copy" 15 layer_absent "omarchy-keyboard-panel"
wait_until "snippets edit persisted the new content" 15 bash -c \
  '[[ $(wl-paste --no-newline) == "docker system prune -af --volumes" ]]'
jq -e '.snippets | length == 1' "$SNIPPETS_STORE" >/dev/null \
  || fail "snippets edit keeps a single stable identity rather than forking a duplicate row"
pass "snippets edit keeps a single stable identity rather than forking a duplicate row"

# ---- a second control snippet, then delete (Delete key on the selected row) --

jq '.snippets += [{id: "control-snippet", name: "Control", content: "untouched"}]' "$SNIPPETS_STORE" >"$SNIPPETS_STORE.tmp"
mv "$SNIPPETS_STORE.tmp" "$SNIPPETS_STORE"

omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel reopens for delete" 15 layer_present "omarchy-keyboard-panel"
wtype "Docker"
wait_until "snippets search finds the row to delete" 15 screen_contains "Docker cleanup"
wtype -k Delete
wait_until "snippets delete confirm opens" 15 screen_contains "Delete"
screenshot "success-snippets-delete-confirm"
wtype -k Return
wait_until "snippets delete confirm closes back to the list" 15 layer_present "omarchy-keyboard-panel"
wtype -k Escape
wait_until "snippets list shows the remaining snippet once the filter clears" 15 screen_contains "Control"
jq -e '[.snippets[] | select(.name == "Docker cleanup")] | length == 0' "$SNIPPETS_STORE" >/dev/null \
  || fail "snippets delete removes only the targeted snippet"
pass "snippets delete removes only the targeted snippet"
jq -e '[.snippets[] | select(.name == "Control" and .content == "untouched")] | length == 1' "$SNIPPETS_STORE" >/dev/null \
  || fail "snippets delete leaves the other snippet untouched"
pass "snippets delete leaves the other snippet untouched"

omarchy-shell shell hide omarchy.snippets >/dev/null
wait_until "snippets panel closes after delete" 15 layer_absent "omarchy-keyboard-panel"

# ---- export / import round trip, then a conflict ------------------------

export_path="$(mktemp -u).json"
omarchy-snippets-export "$export_path"
jq -e '.version == 1 and (.snippets | length == 1)' "$export_path" >/dev/null \
  || fail "snippets export writes the versioned interchange format"
pass "snippets export writes the versioned interchange format"

rm -f "$SNIPPETS_STORE"
omarchy-snippets-import-apply "$export_path" '[]' >/dev/null
jq -e '[.snippets[] | select(.name == "Control" and .content == "untouched")] | length == 1' "$SNIPPETS_STORE" >/dev/null \
  || fail "snippets export/import round trip restores name and content exactly"
pass "snippets export/import round trip restores name and content exactly"

jq -n '{version:1, snippets:[{name:"Control", content:"conflicting content"}]}' > "$export_path.conflict"
omarchy-shell shell summon omarchy.snippets > /dev/null
wait_until "snippets panel reopens for import" 15 layer_present "omarchy-keyboard-panel"
# Tab×3 focuses the import (⤓) button; Return activates it.
wtype -k Tab -k Tab -k Tab -k Return
# The file picker portal dialog opens. Use Ctrl+L to open the path-entry bar,
# type the absolute path to the conflict fixture, then confirm.
wait_until "file picker opens for import" 15 screen_contains "Import Snippets"
wtype -M ctrl -k l -m ctrl
sleep 0.3
wtype "$export_path.conflict"
wtype -k Return
wait_until "snippets import conflict view opens" 15 screen_contains "need a decision"
screenshot "success-snippets-import-conflict"

omarchy-shell shell hide omarchy.snippets > /dev/null
wait_until "snippets panel closes after import preview" 15 layer_absent "omarchy-keyboard-panel"
rm -f "$export_path" "$export_path.conflict"

# ---- single-popout coordination with another bar widget ------------------

omarchy-shell shell summon omarchy.snippets >/dev/null
wait_until "snippets panel opens for popout coordination" 15 layer_present "omarchy-keyboard-panel"
omarchy-shell shell summon omarchy.audio >/dev/null
wait_until "audio panel takes over the shared keyboard-panel layer" 15 screen_contains "Audio"
screenshot "success-snippets-popout-handoff"
omarchy-shell shell hide omarchy.audio >/dev/null
wait_until "audio panel closes" 15 layer_absent "omarchy-keyboard-panel"
