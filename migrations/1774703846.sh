if lspci -nn | grep -q "106b:180[12]" && [[ ! -f /usr/lib/systemd/system-sleep/wifi-resume ]]; then
  echo "Installing WiFi resume hook for T2 MacBook"

  cat <<'HOOK' | sudo tee /usr/lib/systemd/system-sleep/wifi-resume >/dev/null
#!/bin/bash
if [[ $1 == "post" ]]; then
  logger -t wifi-resume "Reloading brcmfmac after resume"
  modprobe -r brcmfmac 2>/dev/null
  modprobe brcmfmac || logger -t wifi-resume "Failed to reload brcmfmac"
fi
HOOK
  sudo chmod +x /usr/lib/systemd/system-sleep/wifi-resume
fi
