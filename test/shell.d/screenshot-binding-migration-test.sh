#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Retire the Super + Shift + S screenshot example' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "screenshot example binding migration exists"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
bindings="$home/.config/hypr/bindings.lua"
mkdir -p "$home/.config/hypr"

run_migration() {
  HOME="$home" bash "$migration" >/dev/null
}

# An install without the file has nothing to repair.
run_migration || fail "migration tolerates a missing bindings.lua"
pass "migration tolerates a missing bindings.lua"

# The uncommented example stacks a second screenshot bind on the new default,
# which makes two picker instances race; the copy goes back to being a comment.
cat >"$bindings" <<'LUA'
-- Personal overrides.
o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
o.bind("SUPER + H", nil, "voxtype record toggle")
LUA
run_migration || fail "migration runs over the uncommented example"
if grep -Eq '^[[:space:]]*o\.bind\("SUPER \+ SHIFT \+ S"' "$bindings"; then
  fail "migration comments out the uncommented screenshot example"
fi
grep -Fq -- '-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")' "$bindings" ||
  fail "migration keeps the retired example visible as a comment"
grep -Fqx 'o.bind("SUPER + H", nil, "voxtype record toggle")' "$bindings" ||
  fail "migration leaves other bindings alone"
pass "migration comments out the uncommented screenshot example"

# Migration state is per-user and the update path can rerun scripts, so a
# second pass over the repaired file must change nothing.
before=$(sha256sum "$bindings" | cut -d' ' -f1)
run_migration || fail "migration reruns cleanly after the repair"
[[ $(sha256sum "$bindings" | cut -d' ' -f1) == "$before" ]] ||
  fail "migration is idempotent after the repair"
pass "migration is idempotent after the repair"

# A customized description still duplicates the default's command, so it gets
# the same treatment.
cat >"$bindings" <<'LUA'
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
LUA
run_migration || fail "migration runs over a described example"
grep -Fq -- '-- o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")' "$bindings" ||
  fail "migration retires the example under a customized description"
pass "migration retires the example under a customized description"

# The chord rebound to any other command is a deliberate user choice: not ours
# to edit. Same for the example still sitting in its shipped, commented form.
cat >"$bindings" <<'LUA'
o.bind("SUPER + SHIFT + S", "Maps", "omarchy-launch-webapp 'https://maps.google.com/'")
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
LUA
before=$(sha256sum "$bindings" | cut -d' ' -f1)
run_migration || fail "migration runs over user rebindings"
[[ $(sha256sum "$bindings" | cut -d' ' -f1) == "$before" ]] ||
  fail "migration leaves user rebindings and commented examples alone"
pass "migration leaves user rebindings and commented examples alone"
