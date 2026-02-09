echo "Enable bluetooth at login screen"

omarchy-pkg-add mkinitcpio-bluetooth

sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block bluetooth encrypt filesystems fsck btrfs-overlayfs)
EOF

sudo tee /etc/mkinitcpio.conf.d/uhid_module.conf <<EOF >/dev/null
MODULES+=(uhid)
EOF

sudo mkinitcpio -P
