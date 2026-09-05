#!/bin/bash
# Copy this Mac's T1 Touch Bar firmware (EFI/APPLE) to an external USB.
# Run ON THIS Mac, in macOS, AFTER first boot when the Touch Bar is on.
# Double-click in Finder or: bash copy-t1-firmware.command
#
# Compatible with stock /bin/bash 3.2 (High Sierra through Sequoia).
# Do not "modernize" this file for bash 5; it has to run on macOS.

set -e

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This needs admin to mount the EFI partition."
    exec sudo /bin/bash "$0" "$@"
  fi
}

is_efi_slice() {
  _info=$(diskutil info "$1" 2>/dev/null) || return 1
  echo "$_info" | grep -q "Partition Type: *EFI" && return 0
  echo "$_info" | grep -q "Content: *EFI" && return 0
  echo "$_info" | grep -q "Volume Name: *EFI" && return 0
  return 1
}

mount_efi() {
  _dev="$1"
  _out=$(diskutil mount "$_dev" 2>&1) || {
    echo "Could not mount $_dev:"
    echo "$_out"
    return 1
  }
  _mp=$(diskutil info "$_dev" | awk -F': *' '/Mount Point:/ {print $2; exit}')
  if [ -z "$_mp" ] || [ "$_mp" = "Not applicable" ]; then
    echo "$_dev has no mount point"
    return 1
  fi
  echo "$_mp"
}

is_external_vol() {
  _vol="$1"
  _info=$(diskutil info "$_vol" 2>/dev/null) || return 1
  echo "$_info" | grep -qi "Internal: *Yes" && return 1
  echo "$_info" | grep -qiE "Protocol: *USB|Device Location: *External|Removable Media: *Removable|Internal: *No"
}

list_efi_devs() {
  diskutil list | awk '/disk[0-9]+s[0-9]+$/ {print $NF}' | while read -r _id; do
    is_efi_slice "$_id" && echo "$_id"
  done
}

list_usb_vols() {
  for _v in /Volumes/*; do
    [ -d "$_v" ] || continue
    _base=$(basename "$_v")
    case "$_base" in
      EFI|Macintosh\ HD|Macintosh\ HD\ -\ Data|Recovery|com.apple.recovery.boot) continue ;;
    esac
    is_external_vol "$_v" && echo "$_v"
  done
}

find_apple_tree() {
  _root="$1"
  if [ -f "$_root/EFI/APPLE/EMBEDDEDOS/combined.memboot" ]; then
    echo "$_root/EFI/APPLE"
    return 0
  fi
  if [ -f "$_root/APPLE/EMBEDDEDOS/combined.memboot" ]; then
    echo "$_root/APPLE"
    return 0
  fi
  return 1
}

echo "T1 Touch Bar firmware copy"
echo "Only copies firmware THIS Mac already wrote to its EFI partition."
echo

need_root "$@"

echo "Looking for EFI/APPLE/EMBEDDEDOS/combined.memboot ..."
echo "(If macOS just finished installing, wait until the Touch Bar lights up, then re-run.)"
echo

SRC=""

for dev in $(list_efi_devs); do
  echo "Checking $dev ..."
  mp=$(mount_efi "$dev") || continue
  apple=$(find_apple_tree "$mp" || true)
  if [ -n "$apple" ]; then
    SRC="$apple"
    echo "Found: $SRC"
    ls -la "$SRC/EMBEDDEDOS" || ls -la "$SRC"
    break
  fi
  echo "  no EMBEDDEDOS on $dev"
done

if [ -z "$SRC" ]; then
  echo
  echo "No combined.memboot on any EFI partition yet."
  echo "Boot this Mac into macOS until the Touch Bar works, stay on Wi-Fi,"
  echo "wait out any 'critical software update', then run this again."
  exit 1
fi

echo
echo "External volumes:"
USB_LIST=$(list_usb_vols || true)
if [ -z "$USB_LIST" ]; then
  echo "  (none found)"
  echo
  echo "Plug in a USB stick, wait for it to appear in Finder, then re-run."
  echo "FAT32, ExFAT, or APFS is fine. Do not pick the EFI partition."
  exit 1
fi

OLDIFS=$IFS
IFS='
'
set -- $USB_LIST
IFS=$OLDIFS
n=$#
i=1
for vol; do
  echo "  $i) $vol"
  i=$((i + 1))
done

DEST=""
if [ "$n" -eq 1 ]; then
  DEST="$1"
  echo
  echo "Using the only external volume: $DEST"
else
  echo
  printf "Number of the USB to copy onto: "
  read -r choice
  case "$choice" in
    ''|*[!0-9]*) echo "Not a number."; exit 1 ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
    echo "Out of range."
    exit 1
  fi
  eval DEST=\$$choice
fi

if [ ! -d "$DEST" ]; then
  echo "Destination vanished: $DEST"
  exit 1
fi

TARGET="$DEST/APPLE"
echo
echo "Copying:"
echo "  $SRC"
echo "  -> $TARGET"
rm -rf "$TARGET"
mkdir -p "$DEST"
cp -R "$SRC" "$TARGET"

if [ ! -f "$TARGET/EMBEDDEDOS/combined.memboot" ]; then
  echo "Copy finished but combined.memboot is missing. Source was incomplete."
  exit 1
fi

echo
echo "OK. On the USB:"
ls -la "$TARGET/EMBEDDEDOS"

echo
echo "Eject the USB in Finder before unplugging."
echo "On Omarchy later:"
echo "  omarchy setup apple touchbar"
echo "then reboot so Apple's EFI can memboot the T1."
