#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')

const items = {
  'setup.default.browser.brave': { id: 'setup.default.browser.brave', when: 'omarchy-pkg-present brave-bin', checked: '[[ "$(omarchy-default-browser)" == "brave" ]]' },
  'setup.default.browser.zen': { id: 'setup.default.browser.zen', when: 'omarchy-pkg-present zen-browser-bin', checked: '[[ "$(omarchy-default-browser)" == "zen" ]]' },
  'plain': { id: 'plain', label: 'No guards' }
}
const script = menu.guardScript(items)

assert(
  script.includes('if { omarchy-pkg-present brave-bin; } >/dev/null 2>&1; then echo setup.default.browser.brave:w:1; else echo setup.default.browser.brave:w:0; fi'),
  'guard script reports a when: as <id>:w:<0|1>'
)
assert(
  script.includes('then echo setup.default.browser.zen:c:1; else echo setup.default.browser.zen:c:0; fi'),
  'guard script reports a checked: as <id>:c:<0|1>'
)
assert(!/\bplain:[wc]:/.test(script), 'guard script skips items with nothing to evaluate')
assertEqual(menu.guardScript({ plain: items.plain }), '', 'guard script is empty when no item carries a guard')

// The cost the menu is paying is per fork, not per expression, so what makes
// the batch fast is asking each command once however many rows want it.
assertEqual(
  (script.match(/^__omarchy_read_\d+=\$\(omarchy-default-browser /gm) || []).length,
  1,
  'guard script reads a value command once for the whole batch'
)
assert(
  script.indexOf('__omarchy_read_') < script.indexOf('if { omarchy-pkg-present'),
  'guard script captures readers before any guard runs, since $() would trap a lazy memo in its subshell'
)
assert(
  menu.guardReaders.every(reader => !script.includes(`$(${reader} `) || reader === 'omarchy-default-browser'),
  'guard script only captures the readers its guards actually ask for'
)

// Every reader named in the shipped menu has to be listed, or it silently
// keeps forking once per row that reads it.
const fs = require('fs')
const defaultItems = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const guardText = defaultItems.map(item => `${item.when}\n${item.checked}`).join('\n')
const repeated = [...new Set(
  (guardText.match(/\$\((omarchy-[a-z0-9-]+)\)/g) || []).map(match => match.slice(2, -1))
)].filter(command => guardText.split(`$(${command})`).length > 2)
assertDeepEqual(
  repeated.filter(command => !menu.guardReaders.includes(command)),
  [],
  'guard readers cover every command the shipped menu reads from more than one row'
)
JS

# The prelude shadows the real commands for the length of the batch, so it has
# to answer exactly as they do -- including for arguments no shipped guard
# passes today, which an extension is free to write tomorrow.
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qq" ]] && { printf '%s\n' brave-bin zen-browser-bin vim; exit 0; }
for pkg in "${@:2}"; do
  case "$pkg" in brave-bin | zen-browser-bin | vim) ;; *) exit 1 ;; esac
done
exit 0
STUB
chmod +x "$stub_dir/pacman"
printf '#!/bin/bash\nexit 0\n' >"$stub_dir/brave"
chmod +x "$stub_dir/brave"

prelude=$(node -e '
const path = require("path")
const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
process.stdout.write(menu.guardScript({ probe: { id: "probe", when: "true" } }))
' | command grep -v '^if {')

for args in "brave-bin" "vim" "absent" "brave-bin vim" "brave-bin absent" ""; do
  for helper in omarchy-pkg-present omarchy-pkg-missing; do
    real=0
    PATH="$stub_dir:$PATH" "$ROOT/bin/$helper" $args >/dev/null 2>&1 || real=$?
    shadowed=0
    PATH="$stub_dir:$PATH" bash -c "$prelude
$helper $args" >/dev/null 2>&1 || shadowed=$?
    ((real == shadowed)) || fail "$helper '$args' answers as the real command" "real: $real, shadowed: $shadowed"
  done
done
pass "guard prelude answers package presence as omarchy-pkg-present and omarchy-pkg-missing do"

for args in "brave" "absent" "brave absent" ""; do
  for helper in omarchy-cmd-present omarchy-cmd-missing; do
    real=0
    PATH="$stub_dir:$PATH" "$ROOT/bin/$helper" $args >/dev/null 2>&1 || real=$?
    shadowed=0
    PATH="$stub_dir:$PATH" bash -c "$prelude
$helper $args" >/dev/null 2>&1 || shadowed=$?
    ((real == shadowed)) || fail "$helper '$args' answers as the real command" "real: $real, shadowed: $shadowed"
  done
done
pass "guard prelude answers command presence as omarchy-cmd-present and omarchy-cmd-missing do"

# A reader is replaced by its captured answer, which has to read back the same
# way -- the value, its exit status, and the trailing newline $() would strip.
reader_check=$(PATH="$stub_dir:$PATH" bash -c '
omarchy-dns() { printf "Cloudflare\n"; return 3; }
export -f omarchy-dns
'"$(node -e '
const path = require("path")
const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
process.stdout.write(menu.guardScript({ probe: { id: "probe", checked: "[[ \"$(omarchy-dns)\" == \"Cloudflare\" ]]" } }))
' | command grep -v '^if {')"'
value=$(omarchy-dns) || status=$?
printf "%s|%s|%s" "$value" "${status:-0}" "$(omarchy-dns | wc -l)"
')
[[ $reader_check == "Cloudflare|3|1" ]] ||
  fail "guard prelude replays a captured reader verbatim" "got: $reader_check"
pass "guard prelude replays a captured reader with its value, exit status, and line"
