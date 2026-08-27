#!/bin/bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
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
  [[ ${2:-} == -c && $# -ge 5 ]] || exit 90
  code=$3
  shell_name=$4
  original_destination=$5
  printf 'transaction %s\n' "$original_destination" >>"$TEST_SUDO_LOG"

  if [[ ${TEST_MUTATE_DEST:-} == "$original_destination" ]]; then
    expected_size=${7:-0}
    case "$original_destination" in
    /usr/share/plymouth/themes/omarchy/*)
      relative=${original_destination#/usr/share/plymouth/themes/omarchy/}
      stage_kind=plymouth
      ;;
    /usr/share/sddm/themes/omarchy/*)
      relative=${original_destination#/usr/share/sddm/themes/omarchy/}
      stage_kind=sddm
      ;;
    *) exit 91 ;;
    esac
    stage_root=$(find "$TEST_STAGES" -mindepth 1 -maxdepth 1 -type d -print -quit)
    source="$stage_root/$stage_kind/$relative"
    /usr/bin/head -c "$expected_size" /dev/zero | /usr/bin/tr '\0' X >"$source"
    printf '%s\n' "$source" >>"$TEST_MUTATE_LOG"
  fi

  mapped_destination="$TEST_FAKE_ROOT$original_destination"
  shift 5

  # The production helper intentionally resets PATH. For this unprivileged
  # simulation only, substitute stat/chown shims so a uid-1000 test directory
  # behaves like the root-owned /usr/share directory used in production.
  code=${code/PATH=\/usr\/bin:\/bin/PATH=$TEST_ROOT_TOOLS:\/usr\/bin:\/bin}
  PATH="$TEST_ROOT_TOOLS:/usr/bin:/bin" \
    /bin/bash -c "$code" "$shell_name" "$mapped_destination" "$@"
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
if [[ ${1:-} == -c && ${2:-} == %u && $last == "$TEST_FAKE_ROOT"* ]]; then
  printf '0\n'
  exit 0
fi
exec /usr/bin/stat "$@"
SH

cat >"$root_tools/chown" <<'SH'
#!/bin/bash
last=${!#}
[[ $last == "$TEST_FAKE_ROOT"* ]] || exit 93
exit 0
SH

cat >"$fake_bin/magick" <<'SH'
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
  mutate_log="$run_dir/mutated.log"
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

run_set() {
  local requested_umask="$1"
  shift
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
      TEST_MUTATE_LOG="$mutate_log" \
      "$@" \
      /bin/bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo.png"
  )
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
    [[ $(grep -Fc "transaction /usr/share/plymouth/themes/omarchy/$asset" "$sudo_log") == 1 ]] || fail "Plymouth $asset is published exactly once"
  done
  for asset in "${sddm_theme_assets[@]}"; do
    destination="$sddm/$asset"
    [[ -f $destination && ! -L $destination ]] || fail "SDDM $asset is a regular file under umask $requested_umask"
    [[ $(stat -c %a "$destination") == 644 ]] || fail "SDDM $asset is mode 0644 under umask $requested_umask"
    [[ -s $destination ]] || fail "SDDM $asset is nonempty under umask $requested_umask"
    [[ $(grep -Fc "transaction /usr/share/sddm/themes/omarchy/$asset" "$sudo_log") == 1 ]] || fail "SDDM $asset is published exactly once"
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

# Swap the first staged source to an unreadable file after all hashes have been
# recorded but in the DEBUG hook immediately before Bash opens the redirection.
# The caller-side open must fail, so sudo never starts and nothing is published.
setup_run
preopen_hook="$run_dir/preopen-hook"
preopen_marker="$run_dir/preopen-marker"
printf 'ROOT ONLY\n' >"$secret"
chmod 000 "$secret"
cat >"$preopen_hook" <<'SH'
if [[ $0 == */bin/omarchy-plymouth-set ]]; then
  set -T
  trap '
    if [[ ${destination:-} == /usr/share/plymouth/themes/omarchy/bullet.png &&
          $BASH_COMMAND == sudo\ /bin/bash\ -c* &&
          ! -e $TEST_PREOPEN_MARKER ]]; then
      mv -T -- "$source" "$source.before-preopen-swap"
      ln -s -- "$TEST_SECRET" "$source"
      printf "swapped\n" >"$TEST_PREOPEN_MARKER"
    fi
  ' DEBUG
fi
SH

output=$(TEST_PREOPEN_MARKER="$preopen_marker" TEST_SECRET="$secret" BASH_ENV="$preopen_hook" run_set 077 env 2>&1)
status=$?
chmod 0600 "$secret"

(( status != 0 )) || fail "an unreadable pre-open source swap aborts publication"
[[ -s $preopen_marker ]] || fail "the pre-open source swap ran deterministically" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' && $(stat -c %a "$theme/bullet.png") == 600 ]] || fail "pre-open failure leaves the live destination unchanged"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "pre-open failure leaves destination-link victims unchanged"
if [[ -e $sudo_log ]] && grep -Fq 'transaction /usr/share/plymouth/themes/omarchy/bullet.png' "$sudo_log"; then
  fail "sudo started despite the caller-side open failure"
fi
assert_no_temporary_files "$fake_root"

pass "an unreadable source swap before open fails without publication"

# Rewrite a staged file in place after Bash has opened it but before root reads
# stdin. Size is preserved, so only the recorded SHA-256 can reject this race.
setup_run
mutate_destination='/usr/share/plymouth/themes/omarchy/omarchy.script'
output=$(run_set 022 env TEST_MUTATE_DEST="$mutate_destination" 2>&1)
status=$?

(( status != 0 )) || fail "an in-place rewrite after open aborts publication"
[[ -s $mutate_log ]] || fail "the post-open in-place rewrite ran"
[[ -L $theme/omarchy.script ]] || fail "failed hash verification leaves the old destination symlink in place"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' && $(stat -c %a "$plymouth_victim") == 600 ]] || fail "failed hash verification leaves the destination-link victim unchanged"
assert_no_temporary_files "$fake_root"

pass "recorded size and SHA-256 reject a same-inode rewrite after open"

# Root rejects both a symlinked parent and a group/world-writable parent before
# it creates a temporary file or touches the live destination.
setup_run
mv "$theme" "$theme.real"
ln -s "$theme.real" "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a symlinked destination parent is rejected"
[[ $(cat "$theme.real/bullet.png") == 'old plymouth bullet.png' ]] || fail "a symlinked parent leaves its target unchanged"
assert_no_temporary_files "$fake_root"

setup_run
chmod 0777 "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a writable destination parent is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable parent leaves its live destination unchanged"
assert_no_temporary_files "$fake_root"

pass "publication rejects symlinked and non-root-writable destination parents"

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
    TEST_MUTATE_LOG="$mutate_log" \
    /bin/bash "$ROOT/bin/omarchy-refresh-plymouth" 2>&1
)
status=$?
(( status == 0 )) || fail "Plymouth refresh succeeds through the safe publisher" "$output"

for asset in "${plymouth_default_assets[@]}"; do
  destination="$theme/$asset"
  cmp -s "$ROOT/default/plymouth/$asset" "$destination" || fail "refresh publishes the packaged $asset bytes"
  [[ -f $destination && ! -L $destination && $(stat -c %a "$destination") == 644 ]] || fail "refresh publishes $asset as a regular mode-0644 file"
  [[ $(grep -Fc "transaction /usr/share/plymouth/themes/omarchy/$asset" "$sudo_log") == 1 ]] || fail "refresh publishes $asset exactly once"
done
[[ -L $sddm/Main.qml && $(cat "$sddm_victim") == 'SDDM VICTIM' ]] || fail "Plymouth refresh leaves SDDM unchanged"
! grep -Fq 'transaction /usr/share/sddm/' "$sudo_log" || fail "Plymouth refresh does not publish SDDM assets"
[[ ! -s $leak_log ]] || fail "refresh never gives root a user-writable source pathname" "$(cat "$leak_log")"

grep -Fq 'sudo /bin/bash -c' "$ROOT/bin/omarchy-plymouth-set" || fail "publisher invokes Bash by its trusted absolute path"
grep -Fq 'PATH=/usr/bin:/bin' "$ROOT/bin/omarchy-plymouth-set" || fail "root helper resets PATH before resolving utilities"

pass "refresh safely publishes its complete fixed asset set, including logos/oma.png"
