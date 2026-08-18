echo "Install Hermes lazy mise stub"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install pipx:hermes-agent hermes
fi

echo "Link Omarchy skills into the Hermes skill directory"

mkdir -p ~/.hermes/skills
for skill in "$OMARCHY_PATH"/default/agents/skills/*/; do
  skill=${skill%/}
  name=${skill##*/}
  ln -sfn "$skill" ~/.hermes/skills/"$name"
done
