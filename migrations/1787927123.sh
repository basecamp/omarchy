echo "Stop Neovim from previewing completions inline without an AI source"

nvim_options="$HOME/.config/nvim/lua/config/options.lua"

if [[ -f $nvim_options ]] && ! grep -qF 'ai_cmp' "$nvim_options"; then
  cat >>"$nvim_options" <<'LUA'

-- Only preview completions inline when an AI source is actually installed.
-- LazyVim's ai_cmp routes AI suggestions through the completion menu and turns
-- on blink's ghost text to preview them; with no AI extra enabled that ghost
-- text just echoes buffer words back at you while you type. Off, the AI extras
-- use their own native inline suggestions instead, still accepted with <Tab>.
vim.g.ai_cmp = false
LUA
fi
