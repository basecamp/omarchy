echo "Add thunderbolt support to boot image"

omarchy-pkg-add bolt

if [[ ! -f /etc/mkinitcpio.conf.d/thunderbolt_module.conf ]]; then
  sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF
fi

if omarchy-cmd-present limine-update; then
  sudo limine-update
fi
