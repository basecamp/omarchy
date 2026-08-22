#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash

payload="$4"
printf '%s' "$payload" >"$OMARCHY_TEST_INPUT_PAYLOAD"
selection_file=$(jq -r '.selectionFile' <<<"$payload")
done_file=$(jq -r '.doneFile' <<<"$payload")
printf 'First line\nSecond line\n' >"$selection_file"
touch "$done_file"
SH

chmod +x "$stub_bin/omarchy-shell"

export PATH="$stub_bin:$PATH"
export OMARCHY_TEST_INPUT_PAYLOAD="$tmp_dir/payload.json"

result=$("$ROOT/bin/omarchy-menu-input" "Screensaver text" --width 520 --multiline)

[[ $result == $'First line\nSecond line' ]] \
  || fail "multiline menu input returns embedded newlines" "$result"
pass "multiline menu input returns embedded newlines"

jq -e '
  .mode == "input" and
  .prompt == "Screensaver text" and
  .width == 520 and
  .multiline == true
' "$OMARCHY_TEST_INPUT_PAYLOAD" >/dev/null \
  || fail "multiline menu input sends its UI contract"
pass "multiline menu input sends its UI contract"
