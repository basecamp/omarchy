# Need gum to query for input
# Note: gum may not be available in Fedora repos, install from GitHub releases
if ! command -v gum &>/dev/null; then
  echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
  sudo rpm --import https://repo.charm.sh/yum/gpg.key

  # yum
  sudo yum install -y gum
fi

# Configure identification
echo -e "\nEnter identification for git and autocomplete..."
export OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ")
export OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ")
