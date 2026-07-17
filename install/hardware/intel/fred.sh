# Enable Flexible Return and Event Delivery on Intel Panther Lake.

DROP_IN="/etc/limine-entry-tool.d/intel-panther-lake-fred.conf"

if omarchy-hw-intel-ptl; then
  if [[ ! -f $DROP_IN ]] || ! grep -q 'fred=on' "$DROP_IN"; then
    sudo mkdir -p /etc/limine-entry-tool.d
    cat <<EOF | sudo tee "$DROP_IN" >/dev/null
# Intel Panther Lake FRED support
KERNEL_CMDLINE[default]+=" fred=on"
EOF
  fi
fi
