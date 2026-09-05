if omarchy-hw-imac20-amdgpu-uclk >/dev/null; then
  echo "Detected iMac20,2 with Radeon Pro 5700 XT. Applying AMDGPU startup workaround..."

  limine_conf="${OMARCHY_IMAC20_AMDGPU_LIMINE_CONF:-/etc/limine-entry-tool.d/imac20-amdgpu-uclk.conf}"
  systemd_unit="${OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT:-/etc/systemd/system/omarchy-imac20-amdgpu-uclk.service}"

  mkdir -p "$(dirname "$limine_conf")" "$(dirname "$systemd_unit")"

  cat >"$limine_conf" <<'EOF'
# Work around SMU initialization failures on the iMac20,2 Radeon Pro 5700 XT.
# Memory-clock features are restored after the display manager starts.
KERNEL_CMDLINE[default]+=" amdgpu.ppfeaturemask=0xfff7bffd"
EOF

  cat >"$systemd_unit" <<'EOF'
[Unit]
Description=Restore AMDGPU memory-clock features on iMac20,2
After=display-manager.service
ConditionKernelCommandLine=amdgpu.ppfeaturemask=0xfff7bffd

[Service]
Type=oneshot
ExecStart=/usr/bin/omarchy-amdgpu-uclk-enable
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

  systemctl daemon-reload
  systemctl enable omarchy-imac20-amdgpu-uclk.service
fi
