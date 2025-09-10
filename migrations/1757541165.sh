echo "Replace Omarchy-specific themes with themes for both Omarchy and Omakub"

export OMACOM_CORE_PATH="$HOME/.local/share/omacom-core"
export PATH="$OMARCHY_PATH/bin:$OMACOM_CORE_PATH/bin:$PATH"

# Pull new omacom-core repository

# Use custom repo if specified, otherwise default to rplopes/omacom-core
# Needs to be replaced with basecamp/omacom-core before releasing
OMACOM_CORE_REPO="${OMACOM_CORE_REPO:-rplopes/omacom-core}"

echo -e "\nCloning omacom-core from: https://github.com/${OMACOM_CORE_REPO}.git"
rm -rf ~/.local/share/omacom-core/
git clone "https://github.com/${OMACOM_CORE_REPO}.git" ~/.local/share/omacom-core >/dev/null

# Use custom branch if instructed, otherwise default to master
OMACOM_CORE_REF="${OMACOM_CORE_REF:-master}"
if [[ $OMACOM_CORE_REF != "master" ]]; then
  echo -e "\eUsing branch: $OMACOM_CORE_REF"
  cd ~/.local/share/omacom-core
  git fetch origin "${OMACOM_CORE_REF}" && git checkout "${OMACOM_CORE_REF}"
  cd -
fi

# Replace installed themes
for f in ~/.local/share/omacom-core/themes/*; do ln -nfs "$f" ~/.config/omarchy/themes/; done