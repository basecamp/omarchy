return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = false,
		priority = 1000,
		config = function()
			require("catppuccin").setup({
				flavour = "mocha", -- other options: "mocha", "frappe", "macchiato"
			})
			vim.cmd.colorscheme("catppuccin-mocha")
		end,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin-mocha",
			background = "light",
		},
	},
}