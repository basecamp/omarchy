echo "Install tuned fan curve for T2 MacBook"

if lspci -nn | grep -q "106b:180[12]" && [[ ! -f /etc/t2fand.conf ]]; then
  cat <<EOF | sudo tee /etc/t2fand.conf >/dev/null
[Fan1]
low_temp=55
high_temp=75
speed_curve=linear
always_full_speed=false
EOF
fi
