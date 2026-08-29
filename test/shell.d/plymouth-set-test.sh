#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source_dir="$test_tmp/source"
theme_dir="$test_tmp/theme"

mkdir -m 0700 "$source_dir"
mkdir -m 0755 "$theme_dir"
touch "$source_dir/logo.png"

cp -a --no-preserve=mode,ownership "$source_dir/." "$theme_dir/"

[[ $(stat -c %a "$theme_dir") == "755" ]] ||
  fail "Plymouth asset copy preserves the theme directory permissions"

grep -Fq \
  'cp -a --no-preserve=mode,ownership "$staging_dir/." "$theme_dir/"' \
  "$ROOT/bin/omarchy-plymouth-set" ||
  fail "omarchy-plymouth-set avoids copying staging directory ownership and mode"

pass "Plymouth asset copy preserves the package-owned directory metadata"

# omarchy-plymouth-set-by-theme hands over a theme's unlock.png from
# ~/.config/omarchy/themes, and both copies below land in world-readable
# /usr/share, so a symlink there would republish whatever it points at.
secret="$test_tmp/secret"
printf 'not yours\n' >"$secret"
ln -s "$secret" "$test_tmp/logo-link.png"

output=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo-link.png" 2>&1)
status=$?

(( status != 0 )) || fail "omarchy-plymouth-set refuses a symlinked logo"
[[ $output == *"symlink"* ]] || fail "omarchy-plymouth-set says why it refused the logo" "$output"

grep -Fq 'sudo cp "$staging_dir/logo.png" "$sddm_dir/logo.png"' "$ROOT/bin/omarchy-plymouth-set" ||
  fail "omarchy-plymouth-set copies the staged logo to SDDM rather than rereading the caller's path as root"

pass "a themed logo cannot republish a file it merely points at"

# Style > Unlock picks a theme by name and hands the answer to
# omarchy-launch-floating-terminal-with-presentation, which joins its arguments
# into a script and runs that with `bash -c`. So the name is shell source
# unless the action quotes it -- and the name is a directory name under
# ~/.config/omarchy/themes, which a theme installed from a git repo gets from
# the repo URL. `a';id;'b` is a legal directory name.
require_command node

unlock_action=$(node -e '
  const fs = require("fs")
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
  process.stdout.write(items.find(item => item.id === "style.unlock").action)
')

[[ -n $unlock_action ]] || fail "the shipped menu still carries a style.unlock action"

stub_dir="$test_tmp/stubs"
mkdir -p "$stub_dir"

canary="$test_tmp/canary"
set_args="$test_tmp/set-args"
reset_marker="$test_tmp/reset-ran"

# What a name that got reparsed would reach. It is a command rather than a
# `touch` so that no quoting of the test's own paths is involved.
cat >"$stub_dir/omarchy-test-canary" <<STUB
#!/bin/bash
printf 'ran\n' >"$canary"
STUB

cat >"$stub_dir/omarchy-plymouth-switcher" <<'STUB'
#!/bin/bash
printf '%s\n' "$OMARCHY_TEST_UNLOCK_NAME"
STUB

# Stands in for the real wrapper, which is a shell-string API: it interpolates
# "$*" into a script and hands that to `bash -c`. The grep below is what keeps
# this stub honest if the wrapper ever stops working that way.
cat >"$stub_dir/omarchy-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
exec bash -c "omarchy-show-logo; $*; omarchy-show-done"
STUB

grep -Fq 'bash -c "$presentation_script"' "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" ||
  fail "the presentation wrapper still runs its argument as a shell string, as the stub above assumes"

# Records what actually arrived, so a name that survived as data is told apart
# from one that arrived split or partly eaten.
cat >"$stub_dir/omarchy-plymouth-set-by-theme" <<'STUB'
#!/bin/bash
printf '%s\n' "$#" "$@" >"$OMARCHY_TEST_SET_ARGS"
STUB

cat >"$stub_dir/omarchy-plymouth-reset" <<'STUB'
#!/bin/bash
printf 'ran\n' >"$OMARCHY_TEST_RESET_MARKER"
STUB

for command in omarchy-show-logo omarchy-show-done; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_dir/$command"
done

chmod +x "$stub_dir"/*

run_unlock_action() {
  rm -f "$canary" "$set_args" "$reset_marker"

  PATH="$stub_dir:$PATH" \
    OMARCHY_TEST_UNLOCK_NAME="$1" \
    OMARCHY_TEST_SET_ARGS="$set_args" \
    OMARCHY_TEST_RESET_MARKER="$reset_marker" \
    bash -c "$unlock_action" >/dev/null 2>&1
}

# A directory name cannot hold a slash or a NUL, and everything else is fair
# game -- these are the shapes that would run on the way to the picker.
for name in "a';omarchy-test-canary;'b" 'a$(omarchy-test-canary)b' 'a`omarchy-test-canary`b' 'a b' '-a'; do
  run_unlock_action "$name"

  [[ ! -e $canary ]] || fail "a theme name reaches the unlock screen as data, not as shell" "ran for: $name"
  [[ $(cat "$set_args" 2>/dev/null) == $'1\n'"$name" ]] ||
    fail "the unlock screen gets the theme name whole" "$name: $(cat "$set_args" 2>/dev/null)"
done

pass "a theme name cannot carry a command into the unlock screen"

# The two ordinary paths still work: a named theme is applied, and `default`
# resets rather than being looked up as a theme.
run_unlock_action "tokyo-night"
[[ $(cat "$set_args" 2>/dev/null) == $'1\ntokyo-night' ]] ||
  fail "an ordinary theme name still reaches omarchy-plymouth-set-by-theme" "$(cat "$set_args" 2>/dev/null)"

run_unlock_action "default"
[[ -e $reset_marker ]] || fail "picking default still resets the unlock screen"
[[ ! -e $set_args ]] || fail "picking default does not look up a theme named default" "$(cat "$set_args")"

pass "the unlock picker still applies a theme and still resets on default"
