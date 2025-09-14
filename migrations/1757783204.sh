echo "Create ~/Work with ./bin in the path for contained projects"

mise_config="$HOME/Work/.mise.toml"

if [[ -f $mise_config ]]; then
  cp $mise_config "$mise_config.bak.$(date +%s)"
fi

source "$OMARCHY_PATH/install/config/mise-work.sh"
