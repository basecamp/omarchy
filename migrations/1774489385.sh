echo "Disable Neovide transparency overrides in nvim"

TRANSPARENCY_FILE="$HOME/.config/nvim/plugin/after/transparency.lua"

if [[ -f $TRANSPARENCY_FILE ]] && ! grep -q "vim.g.neovide" "$TRANSPARENCY_FILE"; then
  temp_file_dir=$(dirname "$TRANSPARENCY_FILE")
  temp_file=$(mktemp "$temp_file_dir/transparency.lua.XXXXXX")

  cat >"$temp_file" <<'EOF'
if vim.g.neovide then
  return
end

EOF

  cat "$TRANSPARENCY_FILE" >>"$temp_file"
  mv "$temp_file" "$TRANSPARENCY_FILE"
fi
