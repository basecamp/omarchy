echo "Enable NPU in voxtype if Intel NPU is available"

if omarchy-cmd-present voxtype; then
  if omarchy-hw-npu; then
    echo "NPU is available, enabling NPU in voxtype"
    voxtype setup npu --enable || true
  fi

  voxtype setup systemd

  systemctl --user restart voxtype
  omarchy-restart-waybar
fi
