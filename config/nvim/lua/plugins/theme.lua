local uv = vim.uv
local file_path = vim.fn.expand("~/.config/omarchy/current/theme/neovim.lua")

-- Default configuration
local default = {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight",
		},
	},
}

-- Try to load custom theme, fallback to default
if uv.fs_stat(file_path) then
	local success, result = pcall(dofile, file_path)
	if success and type(result) == "table" then
		return result
	end
end

return default
