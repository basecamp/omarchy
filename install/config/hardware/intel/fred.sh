# Enable Flexible Return and Event Delivery on Intel Panther Lake.

DROP_IN="/etc/limine-entry-tool.d/intel-panther-lake-fred.conf"
DEFAULT_LIMINE="/etc/default/limine"

if omarchy-hw-intel-ptl; then
  if [[ ! -f "$DROP_IN" ]] || ! grep -q 'fred=on' "$DROP_IN"; then
    mkdir -p /etc/limine-entry-tool.d
    cat > "$DROP_IN" <<EOF
# Intel Panther Lake FRED support
KERNEL_CMDLINE[default]+=" fred=on"
EOF
  fi

  if [[ -f "$DEFAULT_LIMINE" ]] && ! grep -q 'fred=on' "$DEFAULT_LIMINE"; then
    cat "$DROP_IN" >> "$DEFAULT_LIMINE"
  fi
fi
