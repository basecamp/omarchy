#!/bin/bash

# Covers omarchy-hyprland-monitor-rule, which edits per-display rules in
# monitors.lua. The risk it exists to remove is bug #6673 -- a per-display
# setting landing on the catch-all rule and so applying to every display -- so
# most of what is asserted here is about touching one rule and nothing else.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

RULE="$ROOT/bin/omarchy-hyprland-monitor-rule"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# No compositor is consulted: both are supplied so the command never shells out
# to hyprctl during the test.
export OMARCHY_MONITOR_DESCRIPTIONS='[{"name":"DP-1","description":"Dell Inc. AW3225QF HFL3YZ3"}]'
export OMARCHY_MONITOR_SEED='{"mode":"3840x2160@240","position":"0x0","scale":"1.6"}'

assert_equal() {
  local actual="$1" expected="$2" description="$3"

  if [[ $actual == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected
actual:   $actual"
  fi
}

assert_file_equals() {
  local path="$1" expected="$2" description="$3"

  if [[ $(cat "$path") == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected:
$expected

actual:
$(cat "$path")"
  fi
}

write_config() {
  cat >"$OMARCHY_MONITOR_LUA"
}

# ---- Reading ----

export OMARCHY_MONITOR_LUA="$WORK/read.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({
  output = "DP-1",
  scale = 1.6,
  cm = "hdr",
  sdr_max_luminance = 250,
})
hl.monitor({ output = "DP-3", position = "2400x0", transform = 1 })
LUA

assert_equal "$("$RULE" get DP-1 cm)" "hdr" "rule reads a field from a multi-line rule"
assert_equal "$("$RULE" get DP-1 sdr_max_luminance)" "250" "rule reads a numeric field"
assert_equal "$("$RULE" get DP-3 transform)" "1" "rule reads a field from a one-line rule"
assert_equal "$("$RULE" get DP-1 transform)" "" "rule reports an unset field as empty"
assert_equal "$("$RULE" get HDMI-A-1 scale)" "" "rule reports nothing for a display it has no rule for"

# The catch-all speaks for every display, so a per-display read must not answer
# from it -- that conflation is what made a scale set on one display apply to
# all of them.
assert_equal "$("$RULE" get DP-9 mode)" "" "rule never answers from the catch-all"

# ---- Updating in place ----

export OMARCHY_MONITOR_LUA="$WORK/update.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({ output = "DP-3", position = "2400x0", transform = 1 })
LUA

"$RULE" set DP-3 transform=3
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({ output = "DP-3", position = "2400x0", transform = 3 })' "rule updates a field without reflowing the line"

# ---- Adding a field ----

export OMARCHY_MONITOR_LUA="$WORK/add.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-3", position = "2400x0" })
LUA

"$RULE" set DP-3 transform=1
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-3", position = "2400x0", transform = 1 })' "rule adds a field to a one-line rule"

# A rule whose last line carries a trailing comment is the case that breaks
# naive appending: the separating comma ends up inside the comment, where Lua
# cannot see it, and the comment ends up describing the wrong field.
export OMARCHY_MONITOR_LUA="$WORK/comment.lua"
write_config <<'LUA'
hl.monitor({
  output = "DP-1",
  scale = 1.6,
  vrr = 0, -- off: adaptive sync flickers on this panel
})
LUA

"$RULE" set DP-1 transform=2
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({
  output = "DP-1",
  scale = 1.6,
  vrr = 0, -- off: adaptive sync flickers on this panel
  transform = 2,
})' "rule adds a field after a commented line without stealing the comment"

# ---- Removing a field ----

export OMARCHY_MONITOR_LUA="$WORK/remove.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-3", position = "2400x0", transform = 1 })
LUA

"$RULE" unset DP-3 transform
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-3", position = "2400x0" })' "rule removes a trailing field and its separator"

# ---- Creating a rule ----

export OMARCHY_MONITOR_LUA="$WORK/create.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
LUA

"$RULE" set DP-1 cm=hdr
# The seeded geometry matters: a rule that omits position does not inherit the
# catch-all's, so a bare new rule would move the display to 0x0 on next reload.
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })

hl.monitor({ output = "DP-1", mode = "3840x2160@240", position = "0x0", scale = 1.6, cm = "hdr" })' "rule creates a missing rule seeded with live geometry"

# ---- Matching a desc: rule ----

# Users are encouraged to identify displays by description, since connector
# names move between ports. Such a rule must be recognised as the same display
# and keep the identifier its author chose.
export OMARCHY_MONITOR_LUA="$WORK/desc.lua"
write_config <<'LUA'
hl.monitor({ output = "desc:Dell Inc. AW3225QF HFL3YZ3", scale = 1.6 })
LUA

"$RULE" set DP-1 cm=hdr
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "desc:Dell Inc. AW3225QF HFL3YZ3", scale = 1.6, cm = "hdr" })' "rule matches a display written as desc: without rewriting it"

# ---- Value typing ----

export OMARCHY_MONITOR_LUA="$WORK/types.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1" })
LUA

"$RULE" set DP-1 bitdepth=10 cm=hdr min_luminance=0.001 supports_hdr=1
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-1", bitdepth = 10, cm = "hdr", min_luminance = 0.001, supports_hdr = 1 })' "rule writes numbers bare and strings quoted"

# ---- Leaving other rules alone ----

export OMARCHY_MONITOR_LUA="$WORK/isolated.lua"
write_config <<'LUA'
local omarchy_monitor_scale = 1.6

hl.env("GDK_SCALE", "2")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "DP-1", scale = omarchy_monitor_scale })
hl.monitor({ output = "DP-3", scale = omarchy_monitor_scale, transform = 1 })
LUA

"$RULE" set DP-1 transform=2
assert_file_equals "$OMARCHY_MONITOR_LUA" 'local omarchy_monitor_scale = 1.6

hl.env("GDK_SCALE", "2")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.monitor({ output = "DP-1", scale = omarchy_monitor_scale, transform = 2 })
hl.monitor({ output = "DP-3", scale = omarchy_monitor_scale, transform = 1 })' "rule edits one display and leaves the catch-all and siblings untouched"

# ---- Backups ----

export OMARCHY_MONITOR_LUA="$WORK/backup.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA

"$RULE" set DP-1 transform=1
backup_count=$(find "$WORK" -maxdepth 1 -name 'backup.lua.bak.*' | wc -l)
assert_equal "$backup_count" "1" "rule backs the config up before rewriting it"

# A write that changes nothing should not churn backups.
"$RULE" set DP-1 transform=1
backup_count=$(find "$WORK" -maxdepth 1 -name 'backup.lua.bak.*' | wc -l)
assert_equal "$backup_count" "1" "rule does not back up when nothing changes"

# ---- Refusing an unusable target ----

OMARCHY_MONITOR_LUA=/dev/null "$RULE" set DP-1 transform=1 2>/dev/null && status=0 || status=$?
assert_equal "$status" "1" "rule fails cleanly when the config is not a regular file"

# ---- Additional coverage ----

# monitors.lua is executed by Hyprland's Lua config loader, so a rewrite that
# produces text Lua cannot parse takes the user's whole display configuration
# out, not just the field being edited. Every mutation below is checked for
# parseability rather than only for its expected text.
LUAC=$(command -v luac || true)

assert_valid_lua() {
  local path="$1" description="$2" output

  if [[ -z $LUAC ]]; then
    pass "no luac; skipping $description"
    return 0
  fi

  if output=$("$LUAC" -p "$path" 2>&1); then
    pass "$description"
  else
    fail "$description" "$output

file:
$(cat "$path")"
  fi
}

assert_files_equal() {
  local left="$1" right="$2" description="$3"

  if cmp -s "$left" "$right"; then
    pass "$description"
  else
    fail "$description" "$(diff -u "$left" "$right" || true)"
  fi
}

assert_files_differ() {
  local left="$1" right="$2" description="$3"

  if cmp -s "$left" "$right"; then
    fail "$description" "files are identical but should differ"
  else
    pass "$description"
  fi
}

# ---- Round-trip fidelity ----

# Callers toggle fields on and off all session long (the Display panel's HDR
# switch is set-then-unset). Adding a field and removing it again has to leave
# the file byte-identical, or every toggle erodes the user's formatting a little
# more.
export OMARCHY_MONITOR_LUA="$WORK/roundtrip-oneline.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({ output = "DP-1", mode = "3840x2160@240", position = "0x0" })
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/roundtrip-oneline.orig"

"$RULE" set DP-1 cm=hdr
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a one-line rule is still valid Lua after set"
assert_files_differ "$WORK/roundtrip-oneline.orig" "$OMARCHY_MONITOR_LUA" "set on a one-line rule actually changes the file"
"$RULE" unset DP-1 cm
assert_files_equal "$WORK/roundtrip-oneline.orig" "$OMARCHY_MONITOR_LUA" "set then unset restores a one-line rule byte for byte"

export OMARCHY_MONITOR_LUA="$WORK/roundtrip-multiline.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({
  output = "DP-1",
  mode = "3840x2160@240",
  position = "0x0",
})
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/roundtrip-multiline.orig"

"$RULE" set DP-1 cm=hdr
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a multi-line rule is still valid Lua after set"
"$RULE" unset DP-1 cm
assert_files_equal "$WORK/roundtrip-multiline.orig" "$OMARCHY_MONITOR_LUA" "set then unset restores a multi-line rule byte for byte"

# A rule indented with something other than two spaces is the user's choice; a
# new field has to join it rather than impose the command's own indentation.
export OMARCHY_MONITOR_LUA="$WORK/indent.lua"
write_config <<'LUA'
hl.monitor({
    output = "DP-1",
    scale = 1.6,
})
LUA

"$RULE" set DP-1 transform=1
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({
    output = "DP-1",
    scale = 1.6,
    transform = 1,
})' "rule adds a field at the indentation the rule already uses"

# ---- Writing is idempotent ----

# The Display panel re-asserts values it has already written (a slider that
# lands back where it started, a reload that re-applies the current state).
# Writing the value a field already holds must be a no-op: not a reformat, and
# not another backup file.
export OMARCHY_MONITOR_LUA="$WORK/idempotent.lua"
write_config <<'LUA'
hl.monitor({ output = "", scale = 1.6 })
hl.monitor({ output = "DP-1", scale = 1.6, transform = 1 })
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/idempotent.orig"

"$RULE" set DP-1 transform=1
assert_files_equal "$WORK/idempotent.orig" "$OMARCHY_MONITOR_LUA" "setting a field to the value it already holds changes nothing"

"$RULE" set DP-1 transform=3
cp "$OMARCHY_MONITOR_LUA" "$WORK/idempotent.after"
"$RULE" set DP-1 transform=3
assert_files_equal "$WORK/idempotent.after" "$OMARCHY_MONITOR_LUA" "repeating a set is stable the second time"

"$RULE" unset DP-1 transform
cp "$OMARCHY_MONITOR_LUA" "$WORK/idempotent.unset"
"$RULE" unset DP-1 transform
assert_files_equal "$WORK/idempotent.unset" "$OMARCHY_MONITOR_LUA" "unsetting an absent field changes nothing"

# ---- Catch-all isolation ----

# Bug #6673 again, from the read side and the remove side: a field present only
# on the catch-all must look absent for a specific display, and unsetting it for
# that display must not strip it from the rule that speaks for every display.
export OMARCHY_MONITOR_LUA="$WORK/catchall.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6, vrr = 1 })
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/catchall.orig"

assert_equal "$("$RULE" get DP-1 vrr)" "" "a field set only on the catch-all reads as unset for a display"
"$RULE" unset DP-1 vrr
assert_files_equal "$WORK/catchall.orig" "$OMARCHY_MONITOR_LUA" "unsetting a catch-all-only field leaves the catch-all intact"

"$RULE" set DP-1 vrr=0
assert_equal "$("$RULE" get DP-1 vrr)" "0" "the per-display value is what reads back"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "the file is still valid Lua after overriding a catch-all field"
# The catch-all line itself must be exactly as it was: the whole point is that
# one display's choice does not leak to the others.
assert_equal "$(head -n 1 "$OMARCHY_MONITOR_LUA")" 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6, vrr = 1 })' "overriding a field for one display does not rewrite the catch-all"

# `set` addresses a display, never the catch-all, so asking for the catch-all by
# its own empty name must not hand back the shared value either.
assert_equal "$("$RULE" get "" scale)" "" "the catch-all is not readable as a display"

# ---- Duplicate rules ----

# Hyprland applies the later rule, so when a config repeats a display the
# command has to read and write the one that is actually in force; editing the
# earlier one would look like it worked and change nothing.
export OMARCHY_MONITOR_LUA="$WORK/duplicate.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", transform = 1 })
hl.monitor({ output = "DP-1", transform = 2 })
LUA

assert_equal "$("$RULE" get DP-1 transform)" "2" "rule reads the later of two rules for the same display"
"$RULE" set DP-1 transform=3
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-1", transform = 1 })
hl.monitor({ output = "DP-1", transform = 3 })' "rule writes the later of two rules for the same display"

# ---- desc: matching ----

# A desc: string can legally contain the punctuation the rule parser cares
# about. Braces inside it must not be read as rule structure, or the rule ends
# early and the display looks unconfigured.
export OMARCHY_MONITOR_LUA="$WORK/desc-punctuation.lua"
write_config <<'LUA'
hl.monitor({ output = "", scale = 1.6 })
hl.monitor({ output = "desc:Dell {AW} 3225QF", scale = 2, transform = 1 })
LUA

assert_equal "$(OMARCHY_MONITOR_DESCRIPTIONS='[{"name":"DP-1","description":"Dell {AW} 3225QF"}]' "$RULE" get DP-1 scale)" "2" "rule reads a desc: rule whose description contains braces"
OMARCHY_MONITOR_DESCRIPTIONS='[{"name":"DP-1","description":"Dell {AW} 3225QF"}]' "$RULE" unset DP-1 transform
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "", scale = 1.6 })
hl.monitor({ output = "desc:Dell {AW} 3225QF", scale = 2 })' "rule unsets a field on a desc: rule and keeps the desc: identifier"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a desc: rule containing braces is still valid Lua after unset"

# The alias only exists because the compositor told us this connector carries
# that description. Without that link the desc: rule is some other display's,
# and matching it would edit the wrong monitor.
export OMARCHY_MONITOR_LUA="$WORK/desc-unknown.lua"
write_config <<'LUA'
hl.monitor({ output = "desc:Some Other Panel", scale = 2 })
LUA
assert_equal "$("$RULE" get DP-1 scale)" "" "a desc: rule for a different display is not matched"

# ---- Comment and structure preservation ----

# Standalone comments inside and around a rule are the user's notes about their
# own hardware. An edit elsewhere in the rule must not disturb them.
export OMARCHY_MONITOR_LUA="$WORK/comments.lua"
write_config <<'LUA'
-- Displays, left to right.
hl.monitor({
  output = "DP-1",
  -- 240 Hz needs DSC on this cable
  mode = "3840x2160@240",
  scale = 1.6,
})
-- end of displays
LUA

"$RULE" set DP-1 transform=1
assert_file_equals "$OMARCHY_MONITOR_LUA" '-- Displays, left to right.
hl.monitor({
  output = "DP-1",
  -- 240 Hz needs DSC on this cable
  mode = "3840x2160@240",
  scale = 1.6,
  transform = 1,
})
-- end of displays' "rule preserves standalone comments inside and around the rule"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a rule with interleaved comments is still valid Lua after set"

# Removing a field from the middle of a rule must close the gap cleanly: no
# stray comma, no blank line, and the surviving fields in their original order.
export OMARCHY_MONITOR_LUA="$WORK/middle.lua"
write_config <<'LUA'
hl.monitor({
  output = "DP-1",
  scale = 1.6,
  transform = 1,
  vrr = 0,
})
LUA

"$RULE" unset DP-1 transform
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({
  output = "DP-1",
  scale = 1.6,
  vrr = 0,
})' "rule removes a middle field without leaving a hole"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "the file is still valid Lua after removing a middle field"

# A field whose name is a prefix of another must not be confused with it; `scale`
# and `scale_factor` (or `mode` and `modeline`) sit side by side in real configs.
export OMARCHY_MONITOR_LUA="$WORK/prefix.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", scale = 1.6, scale_factor = 3 })
LUA

assert_equal "$("$RULE" get DP-1 scale)" "1.6" "a field name is matched whole, not as a prefix"
"$RULE" set DP-1 scale=2
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-1", scale = 2, scale_factor = 3 })' "setting a field does not touch a field whose name extends it"

# A nested table can repeat a top-level field name. Only the top-level one is a
# monitor setting; rewriting the nested copy would change something else.
export OMARCHY_MONITOR_LUA="$WORK/nested.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", extra = { scale = 99 }, scale = 1.6 })
LUA

assert_equal "$("$RULE" get DP-1 scale)" "1.6" "rule reads the top-level field, not a same-named one nested inside"
"$RULE" set DP-1 scale=2
assert_file_equals "$OMARCHY_MONITOR_LUA" 'hl.monitor({ output = "DP-1", extra = { scale = 99 }, scale = 2 })' "rule writes the top-level field and leaves a nested table alone"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a rule with a nested table is still valid Lua after set"

# ---- Values ----

export OMARCHY_MONITOR_LUA="$WORK/values.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1" })
LUA

"$RULE" set DP-1 vrr=true transform=-1 min_luminance=0.005 mode=raw:omarchy_mode cm='wide gamut'
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a rule written with mixed value types is valid Lua"
assert_equal "$("$RULE" get DP-1 vrr)" "true" "a boolean round-trips through get"
assert_equal "$("$RULE" get DP-1 transform)" "-1" "a negative number round-trips through get"
assert_equal "$("$RULE" get DP-1 min_luminance)" "0.005" "a fractional number round-trips through get"
# `raw:` exists so a rule can reference a Lua variable (the catch-all scale
# local); it must land unquoted or Lua sees a string, not the variable.
assert_equal "$("$RULE" get DP-1 mode)" "omarchy_mode" "a raw: value is written verbatim and reads back unquoted"
assert_equal "$("$RULE" get DP-1 cm)" "wide gamut" "a string with a space round-trips through get"

# ---- Creating a rule ----

# Displays whose scale the user pinned are addressed by name; the created rule
# must carry the requested value rather than the seeded one when they collide on
# the same field, or the request is silently discarded.
export OMARCHY_MONITOR_LUA="$WORK/create-collision.lua"
write_config <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
LUA

"$RULE" set DP-1 scale=2
assert_equal "$("$RULE" get DP-1 scale)" "2" "creating a rule keeps the requested value over the seeded one"
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a freshly created rule is valid Lua"
assert_equal "$(grep -c 'output = "DP-1"' "$OMARCHY_MONITOR_LUA")" "1" "creating a rule adds exactly one rule for the display"
assert_equal "$(head -n 1 "$OMARCHY_MONITOR_LUA")" 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })' "creating a rule leaves the catch-all untouched"

# A display already addressed by desc: must not gain a second, conflicting rule
# under its connector name.
export OMARCHY_MONITOR_LUA="$WORK/create-desc.lua"
write_config <<'LUA'
hl.monitor({ output = "desc:Dell Inc. AW3225QF HFL3YZ3", scale = 1.6 })
LUA

"$RULE" set DP-1 transform=1
assert_equal "$(grep -c 'hl.monitor' "$OMARCHY_MONITOR_LUA")" "1" "a display already written as desc: does not gain a duplicate rule"

# ---- Absent config ----

export OMARCHY_MONITOR_LUA="$WORK/absent.lua"
assert_equal "$("$RULE" get DP-1 scale)" "" "get on a config that does not exist reports nothing"
"$RULE" get DP-1 scale >/dev/null && status=0 || status=$?
assert_equal "$status" "0" "get on a config that does not exist succeeds"

"$RULE" unset DP-1 scale
[[ -e $OMARCHY_MONITOR_LUA ]] && created=yes || created=no
assert_equal "$created" "no" "unset does not conjure a config file"

"$RULE" set DP-1 transform=1
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a config created from nothing is valid Lua"
assert_equal "$("$RULE" get DP-1 transform)" "1" "a rule written into a new config reads back"

# ---- Unknown display ----

export OMARCHY_MONITOR_LUA="$WORK/unknown.lua"
write_config <<'LUA'
hl.monitor({ output = "", scale = 1.6 })
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/unknown.orig"

"$RULE" unset HDMI-A-1 scale
assert_files_equal "$WORK/unknown.orig" "$OMARCHY_MONITOR_LUA" "unset for a display with no rule leaves the config alone"

# ---- Removing every optional field ----

# The Display panel can walk a display back to defaults one field at a time. The
# rule that is left must still be a legal, matchable rule, not an empty husk.
export OMARCHY_MONITOR_LUA="$WORK/strip.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", scale = 1.6, transform = 1, vrr = 0 })
LUA

"$RULE" unset DP-1 scale transform vrr
assert_valid_lua "$OMARCHY_MONITOR_LUA" "a rule stripped of every optional field is valid Lua"
assert_equal "$("$RULE" get DP-1 output)" "DP-1" "a stripped rule still identifies its display"

# ---- Backups ----

# The backup only earns its place if it holds what was there before the write.
export OMARCHY_MONITOR_LUA="$WORK/backup-content.lua"
write_config <<'LUA'
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
cp "$OMARCHY_MONITOR_LUA" "$WORK/backup-content.orig"

"$RULE" set DP-1 scale=2
assert_files_equal "$WORK/backup-content.orig" "$(find "$WORK" -maxdepth 1 -name 'backup-content.lua.bak.*' | head -n 1)" "the backup holds the config as it was before the write"

# ---- Interface ----

assert_equal "$(OMARCHY_MONITOR_LUA=/some/where/monitors.lua "$RULE" path)" "/some/where/monitors.lua" "path reports the config the command edits"

"$RULE" --help >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "0" "--help succeeds"

"$RULE" >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "1" "no arguments is a usage error"

"$RULE" frobnicate DP-1 scale >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "1" "an unknown action is a usage error"

"$RULE" get DP-1 >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "1" "get without a field is a usage error"

"$RULE" set DP-1 >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "1" "set without a field is a usage error"

"$RULE" unset DP-1 >/dev/null 2>&1 && status=0 || status=$?
assert_equal "$status" "1" "unset without a field is a usage error"

# Usage text belongs on stderr when it is an error, so a caller capturing stdout
# does not mistake it for a value.
assert_equal "$("$RULE" get DP-1 2>/dev/null || true)" "" "a usage error writes nothing to stdout"

# ---- Lua the scanner has to actually understand ----
#
# These all come from one root cause: a scanner that knows only `--` line
# comments. It cannot see a --[[ ]] block comment or a [[ ]] long string, so
# commented-out examples read as live rules and quotes inside long strings
# throw off the brace matching.

assert_lua_valid() {
  local path="$1" description="$2"

  if command -v luac >/dev/null; then
    if luac -p "$path" 2>/dev/null; then
      pass "$description"
    else
      fail "$description" "$(cat "$path")"
    fi
  else
    pass "$description (luac absent)"
  fi
}

# A commented-out rule is documentation, not configuration. Editing it instead
# of the live rule silently drops the change and rewrites the example.
export OMARCHY_MONITOR_LUA="$WORK/commented.lua"
write_config <<'LUA'
-- hl.monitor({ output = "DP-1", scale = 9 })
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
"$RULE" set DP-1 scale=2
assert_file_equals "$OMARCHY_MONITOR_LUA" '-- hl.monitor({ output = "DP-1", scale = 9 })
hl.monitor({ output = "DP-1", scale = 2 })' "rule ignores a commented-out rule and edits the live one"

export OMARCHY_MONITOR_LUA="$WORK/block.lua"
write_config <<'LUA'
--[[
hl.monitor({ output = "DP-1", scale = 9 })
]]
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
assert_equal "$("$RULE" get DP-1 scale)" "1.6" "rule reads past a block-commented rule"
"$RULE" set DP-1 transform=1
assert_lua_valid "$OMARCHY_MONITOR_LUA" "rule leaves valid Lua beside a block comment"
assert_equal "$("$RULE" get DP-1 transform)" "1" "rule writes to the live rule beside a block comment"

# A value must stop at its separator. Swallowing the trailing comment means get
# returns the comment text and set deletes it.
export OMARCHY_MONITOR_LUA="$WORK/trailing.lua"
write_config <<'LUA'
hl.monitor({
  output = "DP-1",
  vrr = 0, -- adaptive sync flickers on this panel
})
LUA
assert_equal "$("$RULE" get DP-1 vrr)" "0" "rule reads a value without its trailing comment"

# A long string can contain a quote, which naive quote-tracking reads as the
# start of a string, hiding the rule and appending a duplicate.
export OMARCHY_MONITOR_LUA="$WORK/longstring.lua"
write_config <<'LUA'
local note = [[a " quote]]
hl.monitor({ output = "DP-1", scale = 1.6 })
LUA
"$RULE" set DP-1 transform=1
assert_equal "$(grep -c 'hl.monitor' "$OMARCHY_MONITOR_LUA")" "1" "rule does not duplicate a rule hidden behind a long string"
assert_lua_valid "$OMARCHY_MONITOR_LUA" "rule leaves valid Lua beside a long string"

# Lua allows the last field to have no trailing comma.
export OMARCHY_MONITOR_LUA="$WORK/nocomma.lua"
write_config <<'LUA'
hl.monitor({
  output = "DP-1",
  scale = 1.6
})
LUA
"$RULE" set DP-1 transform=1
assert_lua_valid "$OMARCHY_MONITOR_LUA" "rule leaves valid Lua when the last field had no comma"
assert_equal "$("$RULE" get DP-1 scale)" "1.6" "rule keeps the neighbouring field when the last had no comma"

# ---- Not disturbing the file itself ----

# A config kept in a dotfiles repo is usually symlinked. Replacing the link with
# a regular file orphans the source, and the next dotfiles sync undoes the edit.
export OMARCHY_MONITOR_LUA="$WORK/link.lua"
printf 'hl.monitor({ output = "DP-1", scale = 1.6 })\n' >"$WORK/linked-source.lua"
ln -sf "$WORK/linked-source.lua" "$OMARCHY_MONITOR_LUA"
"$RULE" set DP-1 transform=1
if [[ -L $OMARCHY_MONITOR_LUA ]]; then
  pass "rule writes through a symlink instead of replacing it"
else
  fail "rule writes through a symlink instead of replacing it"
fi
assert_equal "$(grep -c 'transform = 1' "$WORK/linked-source.lua")" "1" "rule writes through to the symlink source"

export OMARCHY_MONITOR_LUA="$WORK/crlf.lua"
printf 'hl.monitor({ output = "DP-1", scale = 1.6 })\r\n' >"$OMARCHY_MONITOR_LUA"
"$RULE" set DP-1 transform=1
if grep -qU $'\r' "$OMARCHY_MONITOR_LUA"; then
  pass "rule leaves CRLF line endings alone"
else
  fail "rule leaves CRLF line endings alone" "$(cat -A "$OMARCHY_MONITOR_LUA")"
fi
