# Exit immediately if a command exits with a non-zero status
set -e

# Give people a chance to retry running the installation
trap 'echo "Omarchy installation failed! You can retry by running: source ~/.local/share/omarchy/install.sh"' ERR

# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do
  echo -e "\nRunning installer: $f"
  source "$f"
done

# Ensure locate is up to date now that everything has been installed
sudo updatedb

# Show summary of failed packages if any
if [ -n "${omarchy_failed_packages+x}" ] && [ ${#omarchy_failed_packages[@]} -gt 0 ]; then
  echo
  gum style --foreground 196 --bold "Failed Package Summary"
  gum style --foreground 196 "The following ${#omarchy_failed_packages[@]} package(s) failed to install:"
  echo
  
  # Remove duplicates and sort
  printf '%s\n' "${omarchy_failed_packages[@]}" | sort -u | while read -r pkg; do
    echo "  • $pkg"
  done
  
  echo
  gum style --foreground 214 "You can try installing these packages manually later with:"
  echo "yay -S <package-name>"
  echo
fi

gum confirm "Reboot to apply all settings?" && reboot
