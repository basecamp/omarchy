echo "Enable the NVIDIA suspend services on 580xx installs so VRAM survives sleep"

# gpu-screen-recorder ships NVreg_PreserveVideoMemoryAllocations=1, which makes
# the NVIDIA driver depend on nvidia-suspend/hibernate/resume to save and
# restore VRAM around sleep. The 580xx legacy driver has no kernel suspend
# notifier support (the open modules handle this automatically), so those
# installs slept without the save and resumed to corrupted GPU state. See
# basecamp/omarchy#8126. Machine-wide repair: no-ops when another user
# already applied it.

if omarchy-pkg-missing nvidia-580xx-utils; then
  exit 0
fi

# Check each unit: is-enabled with multiple units succeeds when at least one
# is enabled, which would let a partially applied enable slip through.
if ! systemctl is-enabled --quiet nvidia-suspend.service ||
  ! systemctl is-enabled --quiet nvidia-hibernate.service ||
  ! systemctl is-enabled --quiet nvidia-resume.service; then
  sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
fi
