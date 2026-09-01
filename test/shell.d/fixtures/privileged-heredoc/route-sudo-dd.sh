sudo dd status=none of=/etc/omarchy/boot.conf <<EOF
cmdline=$boot_params
EOF
