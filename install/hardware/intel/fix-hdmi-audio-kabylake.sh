# Fix missing HDMI/DP audio on systems with Intel Kabylake HDMI codec
# (0x8086280b) where the pins report Devices: 0 and no PCM devices are created.
# Common on some HP / Conexant CX20632 platforms (e.g. Samsung Odyssey G85SB).

# Detect the Intel Kabylake HDMI codec
if ! grep -q "0x8086280b" /proc/asound/card*/codec* 2>/dev/null; then
  return 0 2>/dev/null || exit 0
fi

# Already applied?
if [[ -f /etc/modprobe.d/hda-jack-retask.conf ]]; then
  return 0 2>/dev/null || exit 0
fi

echo "Applying Intel Kabylake HDMI pin fix..."

# Create the firmware patch
sudo mkdir -p /lib/firmware
sudo tee /lib/firmware/hda-jack-retask.fw > /dev/null << 'INNER'
[codec]
0x8086280b 0x80860101 2
[pincfg]
0x05 0x18560070
0x06 0x18560070
0x07 0x18560070
INNER

# Create the modprobe configuration
sudo tee /etc/modprobe.d/hda-jack-retask.conf > /dev/null << 'INNER'
# Added by Omarchy – Intel Kabylake HDMI pin override
# (fixes missing HDMI/DP audio devices)
options snd-hda-intel patch=hda-jack-retask.fw,hda-jack-retask.fw,hda-jack-retask.fw,hda-jack-retask.fw
INNER

# Rebuild initramfs so the firmware is available early
if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
elif command -v mkinitcpio &>/dev/null; then
  sudo mkinitcpio -P
fi

echo "Intel Kabylake HDMI audio fix applied. Reboot required."
