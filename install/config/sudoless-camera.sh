# Setup passwordless sudo for camera device access control.
# First check if KEY_CAMERA is available for the device.
found=false
for f in /sys/class/input/input*/capabilities/key; do
  read -ra b < "$f"

  # KEY_CAMERA (212) -> Block 3, Bit 20
  [[ ${b[3]} ]] && (( 0x${b[3]} & (1 << 20) )) && found=true

  # KEY_CAMERA_ACCESS_* (587-589) -> Block 9, Bits 11-13
  [[ ${b[9]} ]] && (( 0x${b[9]} & 0x3800 )) && found=true

  $found && break
done
if $found; then
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/fuser -k /dev/video*" | sudo tee /etc/sudoers.d/camera-toggle > /dev/null
  sudo chmod 440 /etc/sudoers.d/camera-toggle
  echo "Camera sudoers rule added."
else
  echo "No camera keys found on any input device."
fi
