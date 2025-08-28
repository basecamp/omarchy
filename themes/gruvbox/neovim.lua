return {
	{
		"https://gitlab.com/motaz-shokry/gruvbox.nvim",
		name = "gruvbox",
    	priority = 1000,
		config = function()
			vim.cmd("colorscheme gruvbox")
		end
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "gruvbox",
		},
	},
}
