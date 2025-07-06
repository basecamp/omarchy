# Need gum to query for input
# Note: gum may not be available in Fedora repos, install from GitHub releases
if ! command -v gum &>/dev/null; then
  cd /tmp
  wget https://github.com/charmbracelet/gum/releases/latest/download/gum_0.15.0_Linux_x86_64.tar.gz
  tar -xzf gum_0.15.0_Linux_x86_64.tar.gz
  sudo mv gum /usr/local/bin/
  rm -f gum_0.15.0_Linux_x86_64.tar.gz
  cd -
fi

# Configure identification
echo -e "\nEnter identification for git and autocomplete..."
export OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ")
export OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ")
