# Exit immediately if a command exits with a non-zero status
set -e

# Give people a chance to retry running the installation
trap 'echo "Omarchy installation failed! You can retry by running: source ~/.local/share/omarchy/install.sh"' ERR

# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do
  echo -e "\nRunning installer: $f"
  source "$f"
done

# Report any failed package installations
if [ -n "${omarchy_failed_packages+x}" ] && [ ${#omarchy_failed_packages[@]} -gt 0 ]; then
  gum style --foreground 226 --bold "⚠️  Package Installation Summary"
  echo ""
  
  # Remove duplicates and sort
  unique_failed_packages=($(printf '%s\n' "${omarchy_failed_packages[@]}" | sort -u))
  
  gum style --foreground 196 "Failed to install ${#unique_failed_packages[@]} package(s):"
  echo ""
  
  for pkg in "${unique_failed_packages[@]}"; do
    echo "  • $pkg"
  done
  
  echo ""
  gum style --foreground 39 "You can try installing them manually with:"
  echo "  yay -S ${unique_failed_packages[*]}"
  echo ""
fi

# Ensure locate is up to date now that everything has been installed
sudo updatedb

gum confirm "Reboot to apply all settings?" && reboot