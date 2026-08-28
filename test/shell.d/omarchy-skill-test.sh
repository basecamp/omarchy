#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

validator="$ROOT/default/agents/skills/omarchy/scripts/validate.py"

[[ -x $validator ]] || fail "Omarchy skill validator is executable"

output=$("$validator" --root "$ROOT") || fail "Omarchy skill documentation passes drift validation" "$output"
[[ $output == ok\ -* ]] || fail "Omarchy skill validator reports success" "$output"
pass "Omarchy skill links and command routes match CLI metadata"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/skill"
printf '# Broken\n\nSee [missing](missing.md).\n\n`omarchy imaginary route`\n' >"$scratch/skill/SKILL.md"
printf '{"ok":true,"commands":[]}' >"$scratch/commands.json"

if "$validator" --root "$ROOT" --skill-dir "$scratch/skill" --commands-json "$scratch/commands.json" >"$scratch/out" 2>"$scratch/error"; then
  fail "Omarchy skill validator rejects drift"
fi
grep -q 'missing link target' "$scratch/error" || fail "Omarchy skill validator diagnoses missing links"
grep -q 'unknown command route' "$scratch/error" || fail "Omarchy skill validator diagnoses unknown commands"
pass "Omarchy skill validator diagnoses documentation drift"
