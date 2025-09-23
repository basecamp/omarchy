return {
	{
		name = "theme-hotreload",
		dir = vim.fn.stdpath("config"),
		lazy = false,
		priority = 1000,
		config = function()
			local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

			-- Function to apply transparency after colorscheme change
			local function apply_transparency()
				-- defer it
				vim.defer_fn(function()
					vim.cmd.source(transparency_file)
				end, 5)
			end

			-- Check on startup if the theme do not exists, apply fallback if missing
			local function set_fallback_theme_on_start()
				local ok = pcall(require, "plugins.theme")
				if not ok then
					vim.notify("Theme not found, applying pixel fallback", vim.log.levels.WARN)
					pcall(vim.cmd.colorscheme, "pixel")
					apply_transparency()
				end
			end

			set_fallback_theme_on_start()

			vim.api.nvim_create_autocmd("User", {
				pattern = "LazyReload",
				callback = function()
					-- Clear the theme module cache
					package.loaded["plugins.theme"] = nil

					-- Reload and apply the theme
					vim.schedule(function()
						local ok, theme_config = pcall(require, "plugins.theme")

						if ok then
							-- Find the LazyVim colorscheme config
							for _, spec in ipairs(theme_config) do
								if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
									vim.cmd.colorscheme(spec.opts.colorscheme)
									apply_transparency()
									vim.notify("Applied colorscheme: " .. spec.opts.colorscheme, vim.log.levels.INFO)
									break
								end
							end
						else
							vim.notify(
								"No theme defined or working, applying fallback pixel theme",
								vim.log.levels.WARN
							)
							pcall(vim.cmd.colorscheme, "pixel")
							apply_transparency()
							vim.notify("Applied fallback pixel theme", vim.log.levels.INFO)
						end
					end)
				end,
			})
		end,
	},
}
