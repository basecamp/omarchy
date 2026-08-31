#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

pkgs_candidates=(
  "${OMARCHY_PKGS_PATH:-}"
  "$ROOT/../omarchy-pkgs"
  "$ROOT/../../omarchy-pkgs"
  "$HOME/Work/omarchy/omarchy-pkgs"
  "$HOME/Work/omacom/omarchy-pkgs"
)
pkgs_root=
for candidate in "${pkgs_candidates[@]}"; do
  if [[ -n $candidate && -d $candidate/pkgbuilds/omarchy-settings ]]; then
    pkgs_root=$candidate
    break
  fi
done
[[ -n $pkgs_root ]] || fail "omarchy-pkgs checkout found for ownership-bridge coverage"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/src" "$test_tmp/bin"
ln -s "$ROOT" "$test_tmp/src/omarchy"

# The settings package turns icons into fixed-size PNGs. The bridge test cares
# about payload paths, not image rendering, so keep this package materialization
# independent of the ImageMagick build dependency.
cat >"$test_tmp/bin/magick" <<'STUB'
#!/bin/bash
output=${!#}
output=${output#PNG32:}
install -Dm644 /dev/null "$output"
STUB
chmod +x "$test_tmp/bin/magick"

legacy_paths=(
  etc/docker/daemon.json
  etc/gnupg/dirmngr.conf
  etc/mkinitcpio.conf.d/omarchy_hooks.conf
  etc/mkinitcpio.conf.d/thunderbolt_module.conf
  etc/modprobe.d/omarchy-usb-autosuspend.conf
  etc/sddm.conf.d/10-theme.conf
  etc/sddm.conf.d/10-wayland.conf
  etc/sudoers.d/omarchy-passwd-tries
  etc/sudoers.d/omarchy-tzupdate
  etc/sysctl.d/90-omarchy-file-watchers.conf
  etc/sysctl.d/99-omarchy-sysctl.conf
  etc/systemd/logind.conf.d/10-ignore-power-button.conf
  etc/systemd/resolved.conf.d/10-disable-multicast.conf
  etc/systemd/resolved.conf.d/20-docker-dns.conf
  etc/systemd/system.conf.d/10-faster-shutdown.conf
  etc/systemd/system/user@.service.d/10-faster-shutdown.conf
  etc/systemd/system/docker.service.d/no-block-boot.conf
  etc/systemd/system/plocate-updatedb.service.d/ac-only.conf
  etc/systemd/system.conf.d/20-omarchy-nofile.conf
  etc/systemd/user.conf.d/20-omarchy-nofile.conf
  usr/lib/systemd/system-sleep/unmount-fuse
  usr/local/share/wayland-sessions/omarchy.desktop
  usr/share/sddm/hyprland.lua
)

assert_payload_path() {
  local payload=$1
  local path=$2

  [[ -e $payload/$path || -L $payload/$path ]] || fail "settings payload owns legacy path /$path"
}

materialize_and_check() {
  local package_name=$1
  local pkgbuild=$pkgs_root/pkgbuilds/$package_name/PKGBUILD
  local payload=$test_tmp/$package_name

  [[ -f $pkgbuild ]] || fail "$package_name PKGBUILD exists"
  mkdir -p "$payload"
  (
    export OMARCHY_SRC="$ROOT"
    srcdir="$test_tmp/src"
    pkgdir="$payload"
    PATH="$test_tmp/bin:$PATH"
    source "$pkgbuild"
    package

    for backup_path in "${backup[@]}"; do
      if [[ ! -e $pkgdir/$backup_path && ! -L $pkgdir/$backup_path ]]; then
        echo "stale backup entry in $package_name: $backup_path" >&2
        exit 1
      fi
    done
  ) || fail "$package_name payload materializes cleanly"

  local path source rel
  for path in "${legacy_paths[@]}"; do
    assert_payload_path "$payload" "$path"
  done

  while IFS= read -r -d '' source; do
    rel=${source#"$ROOT/default/plymouth/"}
    assert_payload_path "$payload" "usr/share/plymouth/themes/omarchy/$rel"
  done < <(find "$ROOT/default/plymouth" -type f -print0)

  while IFS= read -r -d '' source; do
    rel=${source#"$ROOT/default/sddm/omarchy/"}
    assert_payload_path "$payload" "usr/share/sddm/themes/omarchy/$rel"
  done < <(find "$ROOT/default/sddm/omarchy" -type f -print0)

  assert_payload_path "$payload" "usr/lib/systemd/system-sleep/omarchy-keyboard-backlight"
  assert_payload_path "$payload" "usr/lib/systemd/system-sleep/omarchy-force-igpu"
  assert_payload_path "$payload" "etc/skel/.config/chromium/EULA Accepted"
  pass "$package_name owns every static path crossing the 3.x package boundary"
}

materialize_and_check omarchy-settings
materialize_and_check omarchy-settings-dev

grep -F '/usr/share/sddm/hyprland.conf' "$ROOT/migrations/1788059374.sh" >/dev/null ||
  fail "the ownership transition retires the unpackaged Omarchy 3 SDDM config"
pass "renamed Omarchy 3 system files have an explicit retirement path"
