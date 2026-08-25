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
