echo "Ensure xe.enable_psr=0 is set in CMDLINE for XPS Panther Lake systems"

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl && [[ -f /etc/default/limine ]]; then
  UPDATED=false

  if grep -Fq 'xe.enable_psr=' /etc/default/limine; then
    if grep -qE 'xe\.enable_psr=[^0[:space:]"]|xe\.enable_psr=0[^[:space:]"]+' /etc/default/limine; then
      sudo sed -Ei 's/(^|[[:space:]])xe\.enable_psr=[^[:space:]"]+/\1xe.enable_psr=0/g' /etc/default/limine
      UPDATED=true
    fi
  else
    echo 'KERNEL_CMDLINE[default]+=" xe.enable_psr=0"' | sudo tee -a /etc/default/limine >/dev/null
    UPDATED=true
  fi

  if $UPDATED; then
    sudo limine-mkinitcpio
  fi
fi
