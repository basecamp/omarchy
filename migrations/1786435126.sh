echo "Install Atuin as a base package and seed its config"

if [[ -f $HOME/.local/bin/atuin ]] && grep -Fq 'mise use -g "atuin"' "$HOME/.local/bin/atuin"; then
  rm -f "$HOME/.local/bin/atuin"
fi

omarchy-pkg-add atuin

[[ -f $HOME/.config/atuin/config.toml ]] || omarchy-refresh-config atuin/config.toml
