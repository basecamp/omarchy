#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

skill="$ROOT/default/agents/skills/omarchy/plugins.md"
parent="$ROOT/default/agents/skills/omarchy/SKILL.md"

if grep -Eq 'reloads plugin code|saved changes reload automatically|plugin code under ~/.config/omarchy/plugins/ hot-reload' "$skill" "$parent"; then
  fail "shipped agent skills do not claim every plugin kind hot-reloads on save"
fi
pass "shipped agent skills do not claim every plugin kind hot-reloads on save"

grep -Fq 'the next time they open' "$skill" ||
  fail "plugins.md says panels and overlays instantiate the next time they open"
grep -Fq 'need `omarchy restart shell`' "$skill" ||
  fail "plugins.md tells agents to restart the shell for bar-widget instance changes"
pass "plugins.md tells agents to restart the shell for bar-widget instance changes"
