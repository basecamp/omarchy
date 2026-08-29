echo "Install Hermes lazy official-installer stub"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-install-hermes-cli --stub
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
  if [[ -d $HOME/.hermes/profiles ]]; then
    for profile in "$HOME"/.hermes/profiles/*/; do
      [[ -d $profile ]] || continue
      mkdir -p "$profile/skills"
      ln -sfn "$skill" "$profile/skills/$name"
    done
  fi
done
