# Shared T1 Touch Bar helpers. Sourced; no shebang, no work on source.
# Firmware is Apple's machine-specific T1 memboot image (EFI/APPLE/EMBEDDEDOS).
# It cannot be redistributed; a USB stick is the handoff from macOS.

t1_marker=EMBEDDEDOS/combined.memboot

t1_collector_path() {
  printf '%s\n' "${OMARCHY_T1_COLLECTOR:-$OMARCHY_PATH/install/hardware/apple/copy-t1-firmware.command}"
}

t1_udev_rule_src() {
  printf '%s\n' "${OMARCHY_T1_UDEV_SRC:-$OMARCHY_PATH/default/udev/apple-t1-touchbar.rules}"
}

t1_udev_rule_dest() {
  printf '%s\n' "${OMARCHY_T1_UDEV_DEST:-/etc/udev/rules.d/90-apple-t1-touchbar.rules}"
}

t1_modules_load_dest() {
  printf '%s\n' "${OMARCHY_T1_MODULES_LOAD:-/etc/modules-load.d/apple-t1-touchbar.conf}"
}

t1_media_roots() {
  local dir
  if [[ -n ${OMARCHY_T1_MEDIA_ROOTS:-} ]]; then
    local IFS=$'\n'
    for dir in $OMARCHY_T1_MEDIA_ROOTS; do
      [[ -d $dir ]] && printf '%s\n' "$dir"
    done
    return
  fi
  for dir in /run/media/*/* /media/*/* /mnt/*; do
    [[ -d $dir ]] && printf '%s\n' "$dir"
  done
}

t1_find_firmware() {
  local dir
  while IFS= read -r dir; do
    if [[ -f $dir/APPLE/$t1_marker ]]; then
      printf '%s\n' "$dir/APPLE"
      return 0
    fi
    if [[ -f $dir/$t1_marker ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done < <(t1_media_roots)
  return 1
}

t1_esp_mount() {
  local mp fstype
  if [[ -n ${OMARCHY_T1_ESP:-} ]]; then
    printf '%s\n' "$OMARCHY_T1_ESP"
    return 0
  fi
  for mp in /boot /boot/efi /efi; do
    findmnt -n "$mp" >/dev/null 2>&1 || continue
    fstype=$(findmnt -n -o FSTYPE "$mp")
    case "$fstype" in
      vfat|fat|msdos)
        printf '%s\n' "$mp"
        return 0
        ;;
    esac
  done
  return 1
}

t1_firmware_present() {
  local esp
  esp=$(t1_esp_mount) || return 1
  [[ -s $esp/EFI/APPLE/$t1_marker ]]
}

t1_copy_firmware() {
  local src=$1 dest_root=$2 dest
  dest="$dest_root/EFI/APPLE"
  mkdir -p "$dest_root/EFI" || return 1
  rm -rf "$dest" || return 1
  # VFAT cannot store Unix ownership; -r not -a so a failed chown does not abort.
  cp -r "$src" "$dest" || return 1
  sync || true
  [[ -s $dest/$t1_marker ]]
}

t1_write_collector() {
  local dest=$1
  cp "$(t1_collector_path)" "$dest/copy-t1-firmware.command"
  chmod +x "$dest/copy-t1-firmware.command"
}

t1_install_wiring() {
  local dest
  dest=$(t1_udev_rule_dest)
  mkdir -p "$(dirname "$dest")"
  cp -f "$(t1_udev_rule_src)" "$dest"
  dest=$(t1_modules_load_dest)
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'EOF'
apple-ibridge
apple-ib-tb
apple-ib-als
EOF
}
