#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'chmod 0600 "$test_tmp/secret" 2>/dev/null || true; rm -rf "$test_tmp"' EXIT

# omarchy-plymouth-set-by-theme hands over a theme's unlock.png from
# ~/.config/omarchy/themes. Both installed copies are world-readable, so a
# symlink there must not republish whatever it points at.
secret="$test_tmp/secret"
printf 'not yours\n' >"$secret"
ln -s "$secret" "$test_tmp/logo-link.png"

output=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo-link.png" 2>&1)
status=$?

((status != 0)) || fail "omarchy-plymouth-set refuses a symlinked logo"
[[ $output == *"symlink"* ]] || fail "omarchy-plymouth-set says why it refused the logo" "$output"

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

# Exercise the full publisher with sudo and ImageMagick shims. Immediately
# after the unprivileged shell opens each staged source, the sudo shim renames
# that source away and replaces its pathname with a symlink to a simulated
# root-only secret. Reading via the inherited stdin descriptor must still
# publish the original bytes. The shim restores the source after each read so
# every Plymouth and SDDM asset gets attacked independently.
fake_bin="$test_tmp/bin"
fake_root="$test_tmp/root"
stages="$test_tmp/stages"
attack_log="$test_tmp/attacked"
sudo_log="$test_tmp/sudo.log"
mkdir -p "$fake_bin" "$fake_root" "$stages"

cat >"$fake_bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_SUDO_LOG"

case "$1" in
tee)
  destination="$2"
  mapped="$TEST_FAKE_ROOT$destination"
  mkdir -p "$(dirname -- "$mapped")"

  stage=$(find "$TEST_STAGES" -mindepth 1 -maxdepth 2 -type f -name omarchy.script -printf '%h\n' | head -n1)
  asset=$(basename -- "$destination")
  source="$stage/$asset"
  pinned="$stage/.pinned-$asset"

  if [[ -n $stage && -f $source && ! -L $source ]]; then
    mv -T -- "$source" "$pinned"
    ln -s "$TEST_SECRET" "$source"
    printf '%s\n' "$asset" >>"$TEST_ATTACK_LOG"
    /usr/bin/tee "$mapped"
    result=$?
    rm -f -- "$source"
    mv -T -- "$pinned" "$source"
    exit "$result"
  fi
  exec /usr/bin/tee "$mapped"
  ;;
chmod)
  exec /usr/bin/chmod "$2" "$TEST_FAKE_ROOT$3"
  ;;
rm)
  destination=${@: -1}
  exec /usr/bin/rm -f -- "$TEST_FAKE_ROOT$destination"
  ;;
plymouth-set-default-theme | limine-mkinitcpio | mkinitcpio)
  exit 0
  ;;
*)
  echo "unexpected sudo command: $*" >&2
  exit 1
  ;;
esac
SH

cat >"$fake_bin/magick" <<'SH'
#!/bin/bash
source="$1"
destination=${@: -1}
[[ $source == "$destination" ]] || /usr/bin/cp -- "$source" "$destination"
SH

cat >"$fake_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$fake_bin"/*

printf 'SIMULATED ROOT-ONLY SECRET\n' >"$secret"
printf 'caller-selected logo\n' >"$test_tmp/logo.png"

output=$(PATH="$fake_bin:$ROOT/bin:$PATH" \
  TMPDIR="$stages" \
  OMARCHY_PATH="$ROOT" \
  TEST_FAKE_ROOT="$fake_root" \
  TEST_STAGES="$stages" \
  TEST_SECRET="$secret" \
  TEST_ATTACK_LOG="$attack_log" \
  TEST_SUDO_LOG="$sudo_log" \
  bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo.png" 2>&1)
status=$?

((status == 0)) || fail "Plymouth publisher succeeds while staged paths are swapped" "$output"

expected_assets=$'bullet.png\nentry-failed.png\nentry.png\nlock-failed.png\nlock.png\nlogo.png\nomarchy.plymouth\nomarchy.script\npreview-unlock.png\nprogress_bar.png\nprogress_box.png'
actual_assets=$(sort -u "$attack_log")
[[ $actual_assets == "$expected_assets" ]] || fail "every staged asset is raced at its privileged publication" "$actual_assets"

! grep -Rqs 'SIMULATED ROOT-ONLY SECRET' "$fake_root" || fail "a replacement symlink was published"
grep -Fq 'caller-selected logo' "$fake_root/usr/share/plymouth/themes/omarchy/logo.png" || fail "the descriptor did not preserve the selected logo bytes"
[[ $(stat -c %a "$fake_root/usr/share/plymouth/themes/omarchy") == 755 ]] || fail "fixed-file publication changed the theme directory mode"

if grep -F "$stages/" "$sudo_log" >/dev/null; then
  fail "a privileged command received a pathname inside the user-writable stage" "$(cat "$sudo_log")"
fi

pass "privileged publication uses pinned descriptors for every staged asset"
