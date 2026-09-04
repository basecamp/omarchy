echo "Link Omarchy agent skills into Hermes skill directories"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
skills_source="$OMARCHY_PATH/default/agents/skills"

[[ -d $skills_source ]] || exit 0

mkdir -p "$HOME/.hermes/skills"

for skill in "$skills_source"/*/; do
  [[ -d $skill ]] || continue
  name=${skill%/}
  name=${name##*/}
  ln -sfn "$skills_source/$name" "$HOME/.hermes/skills/$name"
  if [[ -d $HOME/.hermes/profiles ]]; then
    for profile in "$HOME"/.hermes/profiles/*/; do
      [[ -d $profile ]] || continue
      mkdir -p "$profile/skills"
      ln -sfn "$skills_source/$name" "$profile/skills/$name"
    done
  fi
done
