return {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight",
		},
	},
	{
		"akinsho/bufferline.nvim",
		-- TODO: Remove this once its fixed in lazyvim. This is only a temporary fix, and its onl needed for catppuccin
		init = function()
			local bufline = require("catppuccin.groups.integrations.bufferline")
			bufline.get = bufline.get_theme
		end,
		---@module 'bufferline'
		---@type bufferline.Config
		opts = {
			options = {
				always_show_bufferline = true,
				separator_style = "thick",
				hover = {
					enabled = true,
					delay = 120,
					reveal = { "close" },
				},
			},
		},
	},
}
