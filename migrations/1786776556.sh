echo "Enable palm rejection on T2 MacBook touchpads"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

source_rule="$OMARCHY_PATH/default/udev/apple-t2-touchpad.rules"
rule=/etc/udev/rules.d/99-omarchy-apple-t2-touchpad.rules

if [[ -f $rule ]] && cmp -s "$source_rule" "$rule"; then
  exit 0
fi

sudo install -D -m 0644 "$source_rule" "$rule"

# Libinput must reopen the device to pick up its new integration type.
omarchy-state set reboot-required
