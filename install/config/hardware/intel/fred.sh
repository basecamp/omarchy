# Enable Flexible Return and Event Delivery on Intel Panther Lake.

DROP_IN="/etc/limine-entry-tool.d/intel-panther-lake-fred.conf"
DEFAULT_LIMINE="/etc/default/limine"

if omarchy-hw-intel-ptl; then
  if [[ ! -f $DROP_IN ]] || ! grep -q 'fred=on' "$DROP_IN"; then
    sudo mkdir -p /etc/limine-entry-tool.d
    cat <<EOF | sudo tee "$DROP_IN" >/dev/null
# Intel Panther Lake FRED support
KERNEL_CMDLINE[default]+=" fred=on"
EOF
  fi

  if [[ -f $DEFAULT_LIMINE ]] && ! grep -q 'fred=on' "$DEFAULT_LIMINE"; then
    sudo tee -a "$DEFAULT_LIMINE" < "$DROP_IN" >/dev/null
  fi
fi
