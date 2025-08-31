return {
	{
		"akinsho/bufferline.nvim",
		-- TODO: Remove this once its fixed in lazyvim. This is only a temporary fix, and its onl needed for catppuccin
		init = function()
			local bufline = require("catppuccin.groups.integrations.bufferline")
			function bufline.get()
				return bufline.get_theme()
			end
		end,
	},
}
