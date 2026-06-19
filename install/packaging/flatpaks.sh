# Install Flatpak apps from Flathub.
# These are apps that have no stable RPM/Copr equivalent on Fedora.

echo -e "\e[32m\nInstalling Flatpak applications\e[0m"

flatpak_install() {
  local app_id="$1"
  if ! flatpak info "$app_id" &>/dev/null; then
    echo "Installing Flatpak: $app_id"
    flatpak install -y flathub "$app_id"
  else
    echo "Already installed: $app_id"
  fi
}

# Messaging
flatpak_install org.signal.Signal

# Music
flatpak_install com.spotify.Client

# Notes / Markdown editing
flatpak_install md.obsidian.Obsidian

# Image editing (simple)
flatpak_install com.github.PintaProject.Pinta

# Local file sharing (AirDrop-like)
flatpak_install org.localsend.localsend_app

echo -e "\e[32mFlatpak apps installed\e[0m"
