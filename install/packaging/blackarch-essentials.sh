# Install curated BlackArch tool groups (essentials matching Kali-like default)
# Each group is installed individually so one failure doesn't block the rest.
# Some tools have broken or conflicting dependencies -- that's normal for BlackArch.
echo "Installing BlackArch essential tool groups..."

BLACKARCH_GROUPS=(
  blackarch-recon
  blackarch-scanner
  blackarch-exploitation
  blackarch-webapp
  blackarch-cracker
  blackarch-wireless
  blackarch-sniffer
  blackarch-proxy
  blackarch-forensic
  blackarch-social
  blackarch-fuzzer
)

for group in "${BLACKARCH_GROUPS[@]}"; do
  echo ""
  echo ">> Installing $group..."
  sudo pacman -S --noconfirm --needed --overwrite '*' --ask 4 "$group" || {
    echo ">> Some packages in $group failed to install (dependency conflicts). Skipping broken ones."
  }
done

echo ""
echo "BlackArch essentials installation complete."
