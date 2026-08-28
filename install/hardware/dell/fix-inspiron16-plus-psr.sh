# Fix for pixelated / broken rendering of moving content on Dell Inspiron 16 Plus
# laptops (7620 family) with an Alder Lake Intel Iris Xe iGPU driving the internal
# eDP panel in a hybrid Intel + NVIDIA setup.
#
# The panel's i915 Panel Self-Refresh (PSR2) selective-fetch path fails on these
# panels: the kernel logs "Selective fetch area calculation failed in pipe A" and
# "Port E/TC#2: timeout waiting for PHY ready", and the compositor shows crisp
# static content but pixelated artifacts whenever anything moves. Disabling PSR
# (i915.enable_psr=0) makes the panel refresh cleanly on motion.
#
# gated to the Inspiron 16 Plus family; other models need confirmation the issue
# exists there too before broadening.

if omarchy-hw-dell-inspiron16-plus; then
  sudo mkdir -p /etc/limine-entry-tool.d
  sudo tee /etc/limine-entry-tool.d/dell-inspiron16-plus-psr.conf >/dev/null <<'EOF'
# Dell Inspiron 16 Plus (7620 family) eDP PSR selective-fetch failure workaround
KERNEL_CMDLINE[default]+=" i915.enable_psr=0"
EOF
fi
