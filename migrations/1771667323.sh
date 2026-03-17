echo "Fix colored gutter in nvim by making line numbers transparent"

TRANSPARENCY_FILE="$HOME/.config/nvim/plugin/after/transparency.lua"

if [[ -f $TRANSPARENCY_FILE ]] && ! grep -q "LineNr" "$TRANSPARENCY_FILE"; then
  sed -i '/SignColumn/a vim.api.nvim_set_hl(0, "LineNr", { bg = "none" })\nvim.api.nvim_set_hl(0, "CursorLineNr", { bg = "none" })' "$TRANSPARENCY_FILE"
fi
