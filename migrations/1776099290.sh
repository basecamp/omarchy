echo "Add xe.enable_psr=0 to CMDLINE for XPS Panther Lake systems missing it"

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl && [ -f /etc/default/limine ]; then
  UPDATED=false

  if ! grep -q 'xe.enable_psr' /etc/default/limine; then
    echo 'KERNEL_CMDLINE[default]+=" xe.enable_psr=0"' | sudo tee -a /etc/default/limine >/dev/null
    UPDATED=true
  fi

  if $UPDATED; then
    sudo limine-mkinitcpio
  fi
fi
