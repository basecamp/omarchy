# Apply Intel Kabylake HDMI pin override for systems that never received it.
# Idempotent: no-ops if the codec is absent or the fix is already present.

if ! grep -q "0x8086280b" /proc/asound/card*/codec* 2>/dev/null; then
  return 0 2>/dev/null || exit 0
fi

if [[ -f /etc/modprobe.d/hda-jack-retask.conf ]]; then
  return 0 2>/dev/null || exit 0
fi

echo "Applying Intel Kabylake HDMI audio fix..."

sudo mkdir -p /lib/firmware
sudo tee /lib/firmware/hda-jack-retask.fw > /dev/null << 'INNER'
[codec]
0x8086280b 0x80860101 2
[pincfg]
0x05 0x18560070
0x06 0x18560070
0x07 0x18560070
INNER

sudo tee /etc/modprobe.d/hda-jack-retask.conf > /dev/null << 'INNER'
# Added by Omarchy – Intel Kabylake HDMI pin override
options snd-hda-intel patch=hda-jack-retask.fw,hda-jack-retask.fw,hda-jack-retask.fw,hda-jack-retask.fw
INNER

if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
elif command -v mkinitcpio &>/dev/null; then
  sudo mkinitcpio -P
fi

echo "Intel Kabylake HDMI audio fix applied. A reboot is required."
# Mark reboot required if the helper exists
command -v omarchy-reboot-required &>/dev/null && omarchy-reboot-required
