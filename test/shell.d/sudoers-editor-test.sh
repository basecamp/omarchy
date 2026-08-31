#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

sudoers_file="$ROOT/etc/sudoers.d/omarchy-editor"
packages="$ROOT/install/omarchy-base.packages"

# One Defaults setting, matched whole. This file exists to give visudo a
# fallback editor, so anything else landing in it -- a grant especially -- is a
# change of purpose rather than a tweak of this one.
settings=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $settings == "Defaults editor="* ]] ||
  fail "editor sudoers file carries exactly the editor fallback and nothing else" "got: $settings"
(($(grep -c . <<<"$settings") == 1)) ||
  fail "editor sudoers file carries exactly one setting" "got: $settings"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "editor sudoers setting parses"
fi

pass "editor sudoers file sets nothing but the fallback editor"

# sudo takes a colon-separated list here and skips entries that are not
# installed, but only matches a fully-qualified path -- a bare "nvim" would
# parse and then never match, putting the fallback back at /usr/bin/vi.
editors=${settings#Defaults editor=}
IFS=: read -r -a editor_paths <<<"$editors"
((${#editor_paths[@]} > 0)) || fail "editor fallback names at least one editor"

for editor in "${editor_paths[@]}"; do
  [[ $editor == /* ]] ||
    fail "editor fallback names $editor by absolute path, which is all sudo matches"
done

# The whole point of the fallback is that a root shell with no EDITOR still
# reaches an editor that is on the box. Only the first entry is guaranteed to
# be there, so it has to be one the base install pulls in.
[[ ${editor_paths[0]} == "/usr/bin/nvim" ]] ||
  fail "editor fallback tries nvim first" "got: ${editor_paths[0]}"
grep -Fxq nvim "$packages" ||
  fail "the first editor in the fallback is a package the base install carries"

pass "editor fallback names installed editors by absolute path, nvim first"
