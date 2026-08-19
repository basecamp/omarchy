echo "Install Hermes lazy mise stub"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install pipx:hermes-agent hermes
fi

echo "Link Omarchy skills into the Hermes skill directory"

# Skill symlinks are deliberately unguarded: crash diagnosis is a core
# feature, not an optional preinstall, and the other agent skill symlinks
# (bin/omarchy-provision-user, migrations/1786539345.sh) are created
# unconditionally as well.
mkdir -p "$HOME/.hermes/skills"
for skill in "$OMARCHY_PATH"/default/agents/skills/*/; do
  skill=${skill%/}
  name=${skill##*/}
  ln -sfn "$skill" "$HOME/.hermes/skills/$name"
done
