# Delay iwd startup on Alienware Area-51 to avoid intermittent boot-time
# WLAN_STATUS_ANTI_CLOG_REQUIRED auth failures (status 77).

system_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"

if echo "$system_vendor" | grep -qi "^alienware$" && echo "$product_name" | grep -Eqi "^(alienware 18 area-51|aa18250)$"; then
  echo "Detected $system_vendor $product_name. Applying iwd startup delay workaround."

  sudo install -d /etc/systemd/system/iwd.service.d
  sudo cp "$OMARCHY_PATH/default/systemd/system/iwd.service.d/delay-start.conf" /etc/systemd/system/iwd.service.d/delay-start.conf

  sudo systemctl daemon-reload
fi
