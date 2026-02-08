# Fork replacement for install/login/limine-snapper.sh
# Keeps: mkinitcpio hooks, initramfs rebuild, limine-update
# Removed: snapper setup, limine config overwrite (CachyOS already configures these)

# CachyOS already configures mkinitcpio HOOKS (including plymouth) in /etc/mkinitcpio.conf
# We only add thunderbolt module for early boot support (docks, eGPUs)
sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF

# Re-enable mkinitcpio hooks (disabled in preflight to prevent rebuilds during package install)
echo "Re-enabling mkinitcpio hooks..."

if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

# Rebuild initramfs (includes Plymouth theme for early boot splash)
if command -v limine-mkinitcpio &>/dev/null; then
  sudo limine-mkinitcpio
else
  sudo mkinitcpio -P
fi

# Regenerate limine boot entries with new initramfs
if command -v limine-update &>/dev/null; then
  sudo limine-update
fi
