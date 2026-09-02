# Apple Silicon exposes the internal keyboard and trackpad as HID devices
# created by dockchannel-hid. The dedicated drivers can still be loading when
# those devices first register, so they bind to hid-generic first and are
# destroyed and re-created under the proper driver moments later: the keyboard
# through hid_apple, the trackpad through hid_magicmouse.
#
# That churn reshuffles /dev/input/eventN at the same moment udev,
# systemd-logind and the compositor are starting. On unlucky boots logind
# answers Hyprland's device request with ENOENT for the trackpad node, libinput
# never retries a failed open unless a new udev event arrives, and the trackpad
# stays dead for the whole session. See docs/apple-silicon-trackpad.md.
#
# Early-loading both drivers from the initramfs means they are already
# registered when dockchannel-hid creates its devices: no rebind, no churn, no
# race.
omarchy-hw-apple-silicon || return 0

echo "Detected Apple Silicon Mac: early-loading the Apple HID drivers"

sudo mkdir -p /etc/mkinitcpio.conf.d

# mkinitcpio fails the whole image over a MODULES entry it cannot find, which
# would take every later rebuild with it, including the ones a kernel upgrade
# triggers. So each driver is named only on kernels that build it as a module;
# ending on unset keeps the exit status zero, which mkinitcpio reads as a
# config that sources cleanly.
sudo tee /etc/mkinitcpio.conf.d/apple_hid_modules.conf >/dev/null <<'EOF'
for _omarchy_apple_hid_module in hid_apple hid_magicmouse; do
  modinfo -k "${KERNELVERSION:-$(uname -r)}" "$_omarchy_apple_hid_module" >/dev/null 2>&1 &&
    MODULES+=("$_omarchy_apple_hid_module")
done
unset _omarchy_apple_hid_module
EOF
