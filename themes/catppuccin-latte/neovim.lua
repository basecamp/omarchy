return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
		config = function()
			require("catppuccin").setup({
				flavour = "latte", -- other options: "mocha", "frappe", "macchiato"
			})
			vim.cmd.colorscheme("catppuccin-latte")
		end,
	},
	{
    "akinsho/bufferline.nvim",
    init = function()
        local bufline = require("catppuccin.groups.integrations.bufferline")
        function bufline.get()
          return bufline.get_theme()
        end
      end,
    },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin-latte",
		},
	},
}
