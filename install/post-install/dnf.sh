# Final DNF configuration after all packages are installed.
# Handles Apple T2 Mac hardware which needs an extra repo for Wi-Fi firmware.

# Add Apple T2 firmware repo if needed (T2 Macs have a specific Apple Wi-Fi chip)
if lspci -nn 2>/dev/null | grep -q "106b:180[12]"; then
  echo "Detected Apple T2 hardware — adding Apple T2 Wi-Fi firmware repo..."
  sudo dnf copr enable -y t2linux/t2linux
fi

# Run a final full upgrade to catch anything added by repos enabled mid-install
sudo dnf upgrade -y
