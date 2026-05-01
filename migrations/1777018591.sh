echo "Ensure NVreg_UseKernelSuspendNotifiers is used for hibernation"

if [[ -f /etc/modprobe.d/nvidia.conf ]] && ! grep -q "NVreg_PreserveVideoMemoryAllocations" /etc/modprobe.d/nvidia.conf; then
  sudo tee -a /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia NVreg_PreserveVideoMemoryAllocations=0
options nvidia NVreg_UseKernelSuspendNotifiers=1
EOF
  sudo limine-update
fi
