echo "Add the automatic idle suspend timeout to the shell config"

config_file="$HOME/.config/omarchy/shell.json"

# Customized shell configs are canonical and are not deep-merged with new
# defaults. Materialize the timeout only when it is absent, so an existing
# value—including zero or another non-standard choice—remains the user's.
if [[ -s $config_file ]] && jq -e '
  type == "object" and
  ((.idle == null) or ((.idle | type) == "object")) and
  (((.idle // {}) | has("suspend")) | not)
' "$config_file" >/dev/null 2>&1; then
  tmp=$(mktemp)

  if jq '.idle = ((.idle // {}) + { suspend: 900 })' "$config_file" >"$tmp"; then
    # Write through the path so a shell.json symlinked into a dotfiles repo
    # stays a symlink.
    cat "$tmp" >"$config_file"
  else
    echo "Could not add idle.suspend to $config_file; add it manually."
  fi

  rm -f "$tmp"
fi
