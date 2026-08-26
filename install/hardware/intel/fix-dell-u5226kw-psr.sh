# Display fix for a Dell U5226KW connected to an Intel i915 GPU.
#
# At 6144x2560@120 the panel's PSR (Panel Self Refresh) exit/wake path is
# unreliable on i915: hyprlock's own surface renders fine after unlock, but
# the compositor's next full-desktop atomic commit goes black and stays that
# way until DPMS is toggled off and on enough times to force a fresh commit.
# Not reproduced at 60Hz, but PSR is a module-wide i915 setting with no
# per-mode toggle, so the drop-in applies whenever this monitor is detected
# on i915 regardless of which refresh rate is active.

DROP_IN="/etc/limine-entry-tool.d/dell-u5226kw-psr.conf"

if lspci -k 2>/dev/null | grep -A3 -iE 'vga|3d controller' | grep -q 'Kernel driver in use: i915' &&
  omarchy-hw-dell-u5226kw; then
  if [[ ! -f $DROP_IN ]] || ! grep -q 'enable_psr=0' "$DROP_IN"; then
    sudo mkdir -p /etc/limine-entry-tool.d
    cat <<EOF | sudo tee "$DROP_IN" >/dev/null
# Dell U5226KW PSR workaround (black screen after unlock at 120Hz on i915)
KERNEL_CMDLINE[default]+=" i915.enable_psr=0"
EOF
  fi
fi
