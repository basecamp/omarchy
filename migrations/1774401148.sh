echo "Fix KERNEL_CMDLINE merge behavior in /etc/default/limine"

if [[ -f /etc/default/limine ]]; then
  sudo sed -i 's/^KERNEL_CMDLINE\[default\]="/KERNEL_CMDLINE[default]+="/' /etc/default/limine
fi
