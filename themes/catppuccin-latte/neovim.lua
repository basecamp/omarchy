return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
		config = function()
			require("catppuccin").setup({
				flavour = "latte", -- other options: "mocha", "frappe", "macchiato"
				integrations = {
					cmp = true,
					gitsigns = true,
					harpoon = true,
					illuminate = true,
					lsp_trouble = true,
					markdown = true,
					mason = true,
					native_lsp = {
						enabled = true,
						underlines = {
							errors = { "undercurl" },
							hints = { "undercurl" },
							warnings = { "undercurl" },
							information = { "undercurl" },
						},
					},
					navic = { enabled = true },
					neotree = true,
					notify = true,
					telescope = true,
					treesitter = true,
					which_key = true,
				},
			})
			vim.cmd.colorscheme("catppuccin-latte")
		end,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin-latte",
		},
	},
}
