echo "Stop disabling the Broadcom Wi-Fi offload on Apple Silicon Macs"

# The gate in install/hardware/apple/fix-brcmfmac-supplicant.sh matched an Apple
# machine carrying a brcmfmac PCI ID, and two of those IDs are Apple Silicon
# parts: BCM4378 (14e4:4425) and BCM4387 (14e4:4433). See that leaf for what the
# option does and why those two cannot have it (#7439). Intel Macs keep the
# quirk. This takes it back off the Apple Silicon machines the gate reached,
# including any that ran migrations/1786391100.sh.
conf="${OMARCHY_BRCMFMAC_CONF:-/etc/modprobe.d/brcmfmac.conf}"

[[ $(uname -m) == "aarch64" ]] || exit 0
[[ -f $conf ]] || exit 0

# Only the two parts that gate could have matched. brcmfmac drives plenty of
# other hardware, and a config Omarchy never wrote is not this migration's to
# remove. grep -q would close the pipe on lspci and pipefail would read that
# SIGPIPE as "no such hardware" (#6608), so let lspci finish writing.
lspci -nn | grep -E "14e4:(4425|4433)" >/dev/null || exit 0

# Read through sudo so a root-only file fails the migration loudly and gets
# retried, rather than reading as empty and burning the once-per-user marker.
content="$(sudo cat "$conf")"

# Byte for byte what the leaf wrote, and what migrations/1786391100.sh appended
# after a blank line. Matching the whole block is the ownership test: a line
# the user merged other options onto, a commented-out copy, or any hand-written
# variant no longer matches, and a file like that is not this migration's to
# edit. Those keep the option and its owner removes it by hand.
block="# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000"

[[ $content == "$block" || $content == *$'\n'"$block" ]] || exit 0

# Flag the reboot before touching the file: interrupted here, the worst case is
# a spare reboot prompt rather than an edited config nothing asks to apply.
# modprobe only reads this when brcmfmac next loads, and reloading it now would
# drop the Wi-Fi this update arrived over. An affected machine may also carry
# its own override setting feature_disable=0, which is the driver default and
# redundant once this lands, but removing that file is its owner's call.
omarchy-state set reboot-required

rest=${content%"$block"}
while [[ $rest == *$'\n' ]]; do rest=${rest%$'\n'}; done

if [[ -z $rest ]]; then
  # The file held nothing but Omarchy's block. A symlinked config is emptied
  # through the link rather than removed, so the link its owner set up stays.
  if [[ -L $conf ]]; then
    : | sudo tee "$conf" >/dev/null
  else
    sudo rm -f "$conf"
  fi
else
  # Anything the user kept above the appended block survives. tee writes
  # through a symlink where sed -i would replace it with a regular file.
  printf '%s\n' "$rest" | sudo tee "$conf" >/dev/null
fi
