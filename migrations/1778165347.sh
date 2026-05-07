echo "Install hardware video acceleration for Intel GPUs on non-X Panther Lake systems"

if lspci | grep -iE 'vga|3d|display' | grep -i 'intel' | grep -i 'panther lake' | grep -qi 'intel graphics'; then
  bash "$OMARCHY_PATH/install/config/hardware/intel/video-acceleration.sh"
fi
