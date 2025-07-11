return {
	{ "rebelot/kanagawa.nvim"},
	{ "EdenEast/nightfox.nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "carbonfox",
		},
		init = function()
			-- Custom highlight groups for dashboard colors only
			vim.api.nvim_create_autocmd("ColorScheme", {
				pattern = "*",
				callback = function()
					vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = "#8a8a8d", bold = true }) 
					vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = "#8a8a8d" }) 
					vim.api.nvim_set_hl(0, "SnacksDashboardDir", { fg = "#8a8a8d" }) 
					vim.api.nvim_set_hl(0, "SnacksDashboardFile", { fg = "#8a8a8d" }) 
					vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = "#8a8a8d", italic = true })
					vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = "#ffffff", bold = true })
					vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = "#ffffff" })
					vim.api.nvim_set_hl(0, "SnacksDashboardSpecial", { fg = "#ffffff", bold = true })

				end,
			})
			vim.schedule(function()
				vim.cmd("doautocmd ColorScheme")
			end)
		end,
	},
}