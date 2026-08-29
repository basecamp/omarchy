#!/bin/bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
[[ -n $test_tmp && -d $test_tmp ]] ||
  fail "the test creates its own scratch directory before touching anything"
secret="$test_tmp/secret"
trap 'chmod 0600 "$secret" 2>/dev/null || true; rm -rf -- "$test_tmp"' EXIT

plymouth_theme_assets=(
  bullet.png
  entry.png
  lock.png
  logo.png
  omarchy.plymouth
  omarchy.script
  preview-unlock.png
  progress_bar.png
  progress_box.png
)
plymouth_default_assets=("${plymouth_theme_assets[@]}" logos/oma.png)
sddm_theme_assets=(Main.qml bullet.png entry-failed.png entry.png lock-failed.png lock.png logo.png)

# Keep the refresh allowlist synchronized with every packaged Plymouth asset.
# An added default file must make this test fail until its publication contract
# is explicitly reviewed and included above.
packaged_plymouth_assets=$(find "$ROOT/default/plymouth" -type f -printf '%P\n' | LC_ALL=C sort)
allowlisted_plymouth_assets=$(printf '%s\n' "${plymouth_default_assets[@]}" | LC_ALL=C sort)
[[ $packaged_plymouth_assets == "$allowlisted_plymouth_assets" ]] ||
  fail "Plymouth refresh allowlist differs from the packaged asset set" "$packaged_plymouth_assets"
pass "Plymouth refresh allowlist covers every packaged asset"

# omarchy-plymouth-set-by-theme hands over a theme's unlock.png from
# ~/.config/omarchy/themes. Both installed copies are world-readable, so a
# symlink there must not republish whatever it points at.
printf 'not yours\n' >"$secret"
ln -s "$secret" "$test_tmp/logo-link.png"

output=$(OMARCHY_PATH="$ROOT" /bin/bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo-link.png" 2>&1)
status=$?

(( status != 0 )) || fail "omarchy-plymouth-set refuses a symlinked logo"
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

fake_bin="$test_tmp/bin"
root_tools="$test_tmp/root-tools"
stages="$test_tmp/stages"
mkdir -p "$fake_bin" "$root_tools" "$stages"

cat >"$fake_bin/sudo" <<'SH'
#!/bin/bash
set -u

for argument in "$@"; do
  if [[ $argument == *"$TEST_STAGES"* ]]; then
    printf '%s\n' "$argument" >>"$TEST_LEAK_LOG"
  fi
done

case "$1" in
/bin/bash)
  [[ ${2:-} == -c && $# == 9 ]] || exit 90
  code=$3
  shell_name=$4
  shift 4
  printf 'root transaction\n' >>"$TEST_SUDO_LOG"

  # The production helper intentionally resets PATH. For this unprivileged
  # simulation only, substitute trusted tools and map fixed system destinations
  # under the disposable fake root.
  code=${code/PATH=\/usr\/bin:\/bin/PATH=$TEST_ROOT_TOOLS:\/usr\/bin:\/bin}
  code=${code/theme_dir=\/usr\/share\/plymouth\/themes\/omarchy/theme_dir=$TEST_FAKE_ROOT\/usr\/share\/plymouth\/themes\/omarchy}
  code=${code/sddm_dir=\/usr\/share\/sddm\/themes\/omarchy/sddm_dir=$TEST_FAKE_ROOT\/usr\/share\/sddm\/themes\/omarchy}

  # Each rewrite above silently no-ops if the production text drifts, which
  # would point this simulation at the real /usr/share. Refuse instead.
  [[ $code == *"PATH=$TEST_ROOT_TOOLS:/usr/bin:/bin"* ]] || exit 94
  [[ $code == *"theme_dir=$TEST_FAKE_ROOT/usr/share/plymouth/themes/omarchy"* ]] || exit 94
  [[ $code == *"sddm_dir=$TEST_FAKE_ROOT/usr/share/sddm/themes/omarchy"* ]] || exit 94

  PATH="$TEST_ROOT_TOOLS:/usr/bin:/bin" \
    /bin/bash -c "$code" "$shell_name" "$@"
  ;;
plymouth-set-default-theme | limine-mkinitcpio | mkinitcpio)
  printf 'command %s\n' "$*" >>"$TEST_SUDO_LOG"
  exit 0
  ;;
*)
  echo "unexpected sudo command: $*" >&2
  exit 92
  ;;
esac
SH

cat >"$root_tools/stat" <<'SH'
#!/bin/bash
last=${!#}
if [[ ${1:-} == -c && ${2:-} == %u ]]; then
  if [[ -n ${TEST_UNTRUSTED_SOURCE:-} && $last == "$TEST_UNTRUSTED_SOURCE"* ]]; then
    printf '1000\n'
    exit 0
  fi
  printf '0\n'
  exit 0
fi
if [[ ${1:-} == -c && ${2:-} == %a && $last == /tmp ]]; then
  printf '755\n'
  exit 0
fi
exec /usr/bin/stat "$@"
SH

cat >"$root_tools/chown" <<'SH'
#!/bin/bash
last=${!#}
[[ $last == "$TEST_FAKE_ROOT"* || $last == /tmp/omarchy-plymouth.* ]] || exit 93
exit 0
SH

cat >"$root_tools/magick" <<'SH'
#!/bin/bash
source=$1
destination=${@: -1}
[[ $source == "$destination" ]] || /usr/bin/cp -- "$source" "$destination"
SH

cat >"$fake_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$fake_bin"/* "$root_tools"/*

printf 'caller-selected logo\n' >"$test_tmp/logo.png"

setup_run() {
  run_dir=$(mktemp -d "$test_tmp/run.XXXXXXXX")
  fake_root="$run_dir/root"
  sudo_log="$run_dir/sudo.log"
  leak_log="$run_dir/leaked-stage-path.log"
  theme="$fake_root/usr/share/plymouth/themes/omarchy"
  sddm="$fake_root/usr/share/sddm/themes/omarchy"

  mkdir -p "$theme/logos" "$sddm"
  chmod 0755 \
    "$fake_root/usr" \
    "$fake_root/usr/share" \
    "$fake_root/usr/share/plymouth" \
    "$fake_root/usr/share/plymouth/themes" \
    "$theme" \
    "$theme/logos" \
    "$fake_root/usr/share/sddm" \
    "$fake_root/usr/share/sddm/themes" \
    "$sddm"

  local asset destination
  for asset in "${plymouth_default_assets[@]}"; do
    destination="$theme/$asset"
    printf 'old plymouth %s\n' "$asset" >"$destination"
    chmod 0600 "$destination"
  done
  for asset in "${sddm_theme_assets[@]}" metadata.desktop theme.conf; do
    destination="$sddm/$asset"
    printf 'old sddm %s\n' "$asset" >"$destination"
    chmod 0600 "$destination"
  done

  plymouth_victim="$run_dir/plymouth-victim"
  sddm_victim="$run_dir/sddm-victim"
  legacy_victim="$run_dir/legacy-victim"
  printf 'PLYMOUTH VICTIM\n' >"$plymouth_victim"
  printf 'SDDM VICTIM\n' >"$sddm_victim"
  printf 'LEGACY VICTIM\n' >"$legacy_victim"
  chmod 0600 "$plymouth_victim" "$sddm_victim" "$legacy_victim"

  rm -f "$theme/omarchy.script" "$sddm/Main.qml"
  ln -s "$plymouth_victim" "$theme/omarchy.script"
  ln -s "$sddm_victim" "$sddm/Main.qml"
  ln -s "$legacy_victim" "$sddm/logo.svg"
}

run_set_colors() {
  local requested_umask="$1" background="$2" text="$3"
  shift 3
  (
    umask "$requested_umask"
    PATH="$fake_bin:$ROOT/bin:$PATH" \
      TMPDIR="$stages" \
      OMARCHY_PATH="$ROOT" \
      TEST_FAKE_ROOT="$fake_root" \
      TEST_STAGES="$stages" \
      TEST_ROOT_TOOLS="$root_tools" \
      TEST_SUDO_LOG="$sudo_log" \
      TEST_LEAK_LOG="$leak_log" \
      "$@" \
      /bin/bash "$ROOT/bin/omarchy-plymouth-set" "$background" "$text" "$test_tmp/logo.png"
  )
}

run_set() {
  local requested_umask="$1"
  shift
  run_set_colors "$requested_umask" '#1d2021' '#ebdbb2' "$@"
}

assert_no_temporary_files() {
  local directory="$1" leftovers
  leftovers=$(find "$directory" -name '.*.omarchy-new.*' -print)
  [[ -z $leftovers ]] || fail "failed publication cleans up its root-side temporary file" "$leftovers"
}

for requested_umask in 022 027 077; do
  setup_run
  output=$(run_set "$requested_umask" env 2>&1)
  status=$?
  (( status == 0 )) || fail "Plymouth publisher succeeds under umask $requested_umask" "$output"

  for asset in "${plymouth_theme_assets[@]}"; do
    destination="$theme/$asset"
    [[ -f $destination && ! -L $destination ]] || fail "Plymouth $asset is a regular file under umask $requested_umask"
    [[ $(stat -c %a "$destination") == 644 ]] || fail "Plymouth $asset is mode 0644 under umask $requested_umask"
    [[ -s $destination ]] || fail "Plymouth $asset is nonempty under umask $requested_umask"
  done
  for asset in "${sddm_theme_assets[@]}"; do
    destination="$sddm/$asset"
    [[ -f $destination && ! -L $destination ]] || fail "SDDM $asset is a regular file under umask $requested_umask"
    [[ $(stat -c %a "$destination") == 644 ]] || fail "SDDM $asset is mode 0644 under umask $requested_umask"
    [[ -s $destination ]] || fail "SDDM $asset is nonempty under umask $requested_umask"
  done

  cmp -s "$test_tmp/logo.png" "$theme/logo.png" || fail "Plymouth receives the selected logo under umask $requested_umask"
  cmp -s "$test_tmp/logo.png" "$sddm/logo.png" || fail "SDDM receives the selected logo under umask $requested_umask"
  grep -Fq '#1d2021' "$sddm/Main.qml" || fail "SDDM Main.qml receives the selected background under umask $requested_umask"
  grep -Fq 'Window.SetBackgroundTopColor(0.114, 0.125, 0.129);' "$theme/omarchy.script" || fail "Plymouth script receives the selected background under umask $requested_umask"

  [[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' && $(stat -c %a "$plymouth_victim") == 600 ]] || fail "Plymouth destination symlink never changes its victim"
  [[ $(cat "$sddm_victim") == 'SDDM VICTIM' && $(stat -c %a "$sddm_victim") == 600 ]] || fail "Main.qml destination symlink never changes its victim"
  [[ $(cat "$legacy_victim") == 'LEGACY VICTIM' && $(stat -c %a "$legacy_victim") == 600 ]] || fail "legacy logo.svg removal never changes its victim"
  [[ ! -e $sddm/logo.svg && ! -L $sddm/logo.svg ]] || fail "legacy logo.svg is removed"

  [[ $(cat "$theme/logos/oma.png") == 'old plymouth logos/oma.png' && $(stat -c %a "$theme/logos/oma.png") == 600 ]] || fail "normal theme set does not broaden into the refresh-only nested asset"
  [[ $(cat "$sddm/metadata.desktop") == 'old sddm metadata.desktop' ]] || fail "normal theme set leaves SDDM metadata unchanged"
  [[ $(cat "$sddm/theme.conf") == 'old sddm theme.conf' ]] || fail "normal theme set leaves SDDM theme.conf unchanged"
  [[ ! -s $leak_log ]] || fail "no privileged command receives a user-writable staged pathname" "$(cat "$leak_log")"
  [[ $(stat -c %a "$theme") == 755 && $(stat -c %a "$sddm") == 755 && $(stat -c %a "$theme/logos") == 755 ]] || fail "publication preserves destination directory modes under umask $requested_umask"
  assert_no_temporary_files "$fake_root"
done

pass "every Plymouth and SDDM destination is atomically replaced with mode 0644 across restrictive umasks"

# White uses #ffffff behind #000000 text. A direct two-expression sed first
# writes the white background and then consumes it as if it were the template's
# text placeholder, producing a black-on-black greeter.
setup_run
output=$(run_set_colors 022 '#ffffff' '#000000' env 2>&1)
status=$?
(( status == 0 )) || fail "White theme publishes through the safe asset pipeline" "$output"
grep -Fq 'color: "#ffffff"' "$sddm/Main.qml" || fail "White theme preserves its SDDM background color"
if grep -Fq '__OMARCHY_SDDM_' "$sddm/Main.qml"; then
  fail "SDDM color substitution left an intermediate token behind"
fi
pass "White theme keeps a white SDDM background instead of becoming black-on-black"

# Swap the selected logo to an unreadable file in the DEBUG hook immediately
# before Bash opens its descriptor. The caller-side open must fail, so sudo
# never starts and nothing is published.
setup_run
preopen_hook="$run_dir/preopen-hook"
preopen_marker="$run_dir/preopen-marker"
printf 'ROOT ONLY\n' >"$secret"
chmod 000 "$secret"
cat >"$preopen_hook" <<'SH'
if [[ $0 == */bin/omarchy-plymouth-set ]]; then
  set -T
  trap '
    if [[ $BASH_COMMAND == exec* && $BASH_COMMAND == *logo_fd* &&
          ! -e $TEST_PREOPEN_MARKER ]]; then
      mv -T -- "$logo_path" "$logo_path.before-preopen-swap"
      ln -s -- "$TEST_SECRET" "$logo_path"
      printf "swapped\n" >"$TEST_PREOPEN_MARKER"
    fi
  ' DEBUG
fi
SH

output=$(TEST_PREOPEN_MARKER="$preopen_marker" TEST_SECRET="$secret" BASH_ENV="$preopen_hook" run_set 077 env 2>&1)
status=$?
chmod 0600 "$secret"
rm -f "$test_tmp/logo.png"
mv "$test_tmp/logo.png.before-preopen-swap" "$test_tmp/logo.png"

(( status != 0 )) || fail "an unreadable pre-open source swap aborts publication"
[[ -s $preopen_marker ]] || fail "the pre-open source swap ran deterministically" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' && $(stat -c %a "$theme/bullet.png") == 600 ]] || fail "pre-open failure leaves the live destination unchanged"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "pre-open failure leaves destination-link victims unchanged"
if [[ -e $sudo_log ]] && grep -Fq 'root transaction' "$sudo_log"; then
  fail "sudo started despite the caller-side open failure"
fi
assert_no_temporary_files "$fake_root"

pass "an unreadable source swap before open fails without publication"

# Plant both a malicious script and a root-file symlink where the old
# caller-owned stage lived. The privileged transaction must ignore that tree:
# executable/config assets come only from its root-trusted source and are built
# in its own root-owned stage.
setup_run
attacker_stage="$stages/tmp.attacker"
mkdir -p "$attacker_stage/plymouth"
printf 'MALICIOUS BOOT SCRIPT\n' >"$attacker_stage/plymouth/omarchy.script"
ln -s "$secret" "$attacker_stage/plymouth/logo.png"

output=$(run_set 022 env 2>&1)
status=$?

(( status == 0 )) || fail "a planted caller-owned stage cannot disrupt publication" "$output"
! grep -Rqs 'MALICIOUS BOOT SCRIPT' "$fake_root" || fail "caller-owned staged content reached the boot theme"
[[ -f $theme/omarchy.script && ! -L $theme/omarchy.script ]] || fail "the trusted Plymouth script replaces the planted destination symlink"
grep -Fq 'Window.SetBackgroundTopColor(0.114, 0.125, 0.129);' "$theme/omarchy.script" || fail "the installed script was derived from the trusted packaged source"
unexpected_stages=$(find "$stages" -mindepth 1 -maxdepth 1 ! -name tmp.attacker -print)
[[ -z $unexpected_stages ]] || fail "the caller created an authoritative staging directory" "$unexpected_stages"
assert_no_temporary_files "$fake_root"

pass "caller-owned content cannot enter the root-owned boot-image stage"

# A user-owned source checkout would put the same pre-hash race on the input
# side of the root stage. Refuse it before any fixed destination is replaced.
setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT/default/plymouth" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned packaged source tree is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "an untrusted packaged source leaves the live theme unchanged"
[[ -L $theme/omarchy.script && $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "an untrusted source cannot replace executable Plymouth content"
[[ $output == *"refusing to publish"* ]] || fail "a rejected packaged source says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root rejects packaged assets that a desktop process could rewrite"

# omarchy dev link points OMARCHY_PATH at a checkout the desktop user owns, so
# this refusal fires on a working machine, not only under attack. Every check in
# the privileged transaction is a bare assertion that aborts under set -e, so
# without a diagnostic the whole Plymouth menu would just close in silence.
setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned OMARCHY_PATH is rejected"
[[ $output == *"is not root-owned"* ]] || fail "the refusal names the untrusted source tree" "$output"
[[ $output == *"omarchy dev unlink"* ]] || fail "the refusal names the way back to a trusted tree" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a user-owned OMARCHY_PATH leaves the live theme unchanged"
assert_no_temporary_files "$fake_root"

pass "a development checkout is refused with an explanation instead of in silence"

# Root rejects both a symlinked parent and a group/world-writable parent before
# it creates a temporary file or touches the live destination.
setup_run
mv "$theme" "$theme.real"
ln -s "$theme.real" "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a symlinked destination parent is rejected"
[[ $(cat "$theme.real/bullet.png") == 'old plymouth bullet.png' ]] || fail "a symlinked parent leaves its target unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected symlinked parent says why it refused" "$output"
assert_no_temporary_files "$fake_root"

setup_run
chmod 0777 "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a writable destination parent is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable parent leaves its live destination unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected writable parent says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "publication rejects symlinked and non-root-writable destination parents"

# Walking the whole chain, not just the immediate parent, is what closes the
# rename race: a writable ancestor lets an attacker swap an entire validated
# directory out from under the leaf. Leave the destination itself pristine so
# only the ancestor can be at fault.
setup_run
chmod 0777 "$fake_root/usr/share/plymouth"
output=$(run_set 022 env 2>&1)
status=$?
chmod 0755 "$fake_root/usr/share/plymouth"

(( status != 0 )) || fail "a writable destination ancestor is rejected" "$output"
[[ $(stat -c %a "$theme") == 755 ]] || fail "only the ancestor, not the destination, was untrustworthy"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable ancestor leaves the live destination unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected ancestor says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "publication walks the whole parent chain, not only the immediate parent"

# Refresh uses the same publisher but its explicit contract includes the
# packaged nested logos/oma.png asset. It must not touch the SDDM theme.
setup_run
output=$(
  PATH="$fake_bin:$ROOT/bin:$PATH" \
    TMPDIR="$stages" \
    OMARCHY_PATH="$ROOT" \
    TEST_FAKE_ROOT="$fake_root" \
    TEST_STAGES="$stages" \
    TEST_ROOT_TOOLS="$root_tools" \
    TEST_SUDO_LOG="$sudo_log" \
    TEST_LEAK_LOG="$leak_log" \
    /bin/bash "$ROOT/bin/omarchy-refresh-plymouth" 2>&1
)
status=$?
(( status == 0 )) || fail "Plymouth refresh succeeds through the safe publisher" "$output"

for asset in "${plymouth_default_assets[@]}"; do
  destination="$theme/$asset"
  cmp -s "$ROOT/default/plymouth/$asset" "$destination" || fail "refresh publishes the packaged $asset bytes"
  [[ -f $destination && ! -L $destination && $(stat -c %a "$destination") == 644 ]] || fail "refresh publishes $asset as a regular mode-0644 file"
done
[[ -L $sddm/Main.qml && $(cat "$sddm_victim") == 'SDDM VICTIM' ]] || fail "Plymouth refresh leaves SDDM unchanged"
! grep -Fq 'transaction /usr/share/sddm/' "$sudo_log" || fail "Plymouth refresh does not publish SDDM assets"
[[ ! -s $leak_log ]] || fail "refresh never gives root a user-writable source pathname" "$(cat "$leak_log")"

grep -Fq 'sudo /bin/bash -c' "$ROOT/bin/omarchy-plymouth-set" || fail "publisher invokes Bash by its trusted absolute path"
grep -Fq 'PATH=/usr/bin:/bin' "$ROOT/bin/omarchy-plymouth-set" || fail "root helper resets PATH before resolving utilities"

pass "refresh safely publishes its complete fixed asset set, including logos/oma.png"
