echo "Restore wired Xbox controller support alongside xpadneo"

legacy_blacklist="${OMARCHY_XPAD_BLACKLIST:-/etc/modprobe.d/blacklist-xpad.conf}"

if omarchy-pkg-present xpadneo-dkms && [[ -f $legacy_blacklist ]] && [[ $(<"$legacy_blacklist") == "blacklist xpad" ]]; then
  sudo rm -f -- "$legacy_blacklist"
  sudo modprobe xpad
fi
