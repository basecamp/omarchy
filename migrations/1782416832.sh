echo "Install btop with Intel Xe GPU support"

if omarchy-hw-intel-xe; then
  bash "$OMARCHY_PATH/install/config/hardware/intel/btop-xe.sh"

  if [[ -f ~/.config/btop/btop.conf ]]; then
    sed -i 's/^show_gpu_info = "Auto"/show_gpu_info = "On"/' ~/.config/btop/btop.conf
    sed -i 's/^shown_boxes = "cpu mem net proc gpu0"/shown_boxes = "cpu mem net proc"/' ~/.config/btop/btop.conf
  fi
fi
