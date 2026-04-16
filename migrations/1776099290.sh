echo "Ensure xe.enable_psr=0 is set in CMDLINE for XPS Panther Lake systems"

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl && [[ -f /etc/default/limine ]]; then
  if ! grep -Fq 'xe.enable_psr=0' /etc/default/limine; then
    echo 'KERNEL_CMDLINE[default]+=" xe.enable_psr=0"' | sudo tee -a /etc/default/limine >/dev/null
    sudo limine-mkinitcpio
  fi
fi
