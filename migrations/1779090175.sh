echo "Guarded masking of NetworkManager-wait-online.service"

if systemctl list-unit-files | grep -q NetworkManager-wait-online; then
  systemctl disable --now NetworkManager-wait-online.service 2>/dev/null || true
  systemctl mask NetworkManager-wait-online.service
  echo "Masked NetworkManager-wait-online.service"
else
  echo "NetworkManager-wait-online not present, skipping"
fi
