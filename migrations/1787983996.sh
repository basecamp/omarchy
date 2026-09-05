echo "Apply Steam Input permissions to uinput"

uinput_device="${OMARCHY_UINPUT_DEVICE:-/dev/uinput}"
uinput_rule="${OMARCHY_UINPUT_RULE:-/etc/tmpfiles.d/omarchy-uinput.conf}"
uinput_owner="${OMARCHY_UINPUT_OWNER:-root}"
uinput_group="${OMARCHY_UINPUT_GROUP:-input}"

[[ -e $uinput_device ]] || exit 0
uinput_state=$(stat -c '%a %U %G' "$uinput_device") || exit 0
[[ $uinput_state != "660 $uinput_owner $uinput_group" ]] || exit 0

sudo systemd-tmpfiles --create "$uinput_rule"
