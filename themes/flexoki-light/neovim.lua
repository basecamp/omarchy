return {
	{
		"kepano/flexoki-neovim",
		name = "flexoki",
		config = function()
			vim.api.nvim_set_option_value("background", "light", {})
		end,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "flexoki-light",
		},
	},
}
