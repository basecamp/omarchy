echo "Mark T2 Mac built-in trackpads as internal so disable-while-typing works"

# t2bce_vhci USB pads are udev-external. Existing T2 installs already have
# linux-t2 and the keyboard quirk; they still need this udev rule.

if ! omarchy-hw-t2; then
  exit 0
fi

src="${OMARCHY_PATH}/install/hardware/apple"
rule_dst="${OMARCHY_T2_TOUCHPAD_RULE:-/etc/udev/rules.d/99-omarchy-t2-touchpad.rules}"

if [[ ! -f $rule_dst ]]; then
  sudo install -Dm644 "$src/99-omarchy-t2-touchpad.rules" "$rule_dst"
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=input --action=change
fi
