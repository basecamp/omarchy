return {
	{ -- requires plugins in lua/plugins/treesitter.lua and lua/plugins/lsp.lua
		-- for complete functionality (language features)
		"quarto-dev/quarto-nvim",
		dev = false,
		opts = {
			lspFeatures = {
				enabled = true,
				chunks = "curly",
			},
			codeRunner = {
				enabled = true,
				default_method = "slime",
				never_run = { "yaml" },
			},
		},
		dependencies = {
			-- for language features in code cells
			-- configured in lua/plugins/lsp.lua
			"jmbuhr/otter.nvim",
		},
	},

	-- { -- directly open ipynb files as quarto docuements
	-- 	-- and convert back behind the scenes
	-- 	"GCBallesteros/jupytext.nvim",
	-- 	opts = {
	-- 		lazy = false,
	-- 		custom_language_formatting = {
	-- 			python = {
	-- 				extension = "qmd",
	-- 				style = "quarto",
	-- 				force_ft = "quarto",
	-- 			},
	-- 			r = {
	-- 				extension = "qmd",
	-- 				style = "quarto",
	-- 				force_ft = "quarto",
	-- 			},
	-- 		},
	-- 	},
	-- },

	{ -- paste an image from the clipboard or drag-and-drop
		"HakonHarnes/img-clip.nvim",
		event = "BufEnter",
		ft = { "markdown", "quarto" },
		opts = {
			default = {
				dir_path = "img",
			},
			filetypes = {
				markdown = {
					url_encode_path = true,
					template = "![$CURSOR]($FILE_PATH)",
					drag_and_drop = {
						download_images = false,
					},
				},
				quarto = {
					url_encode_path = true,
					template = "![$CURSOR]($FILE_PATH)",
					drag_and_drop = {
						download_images = false,
					},
				},
			},
		},
		config = function(_, opts)
			require("img-clip").setup(opts)
			vim.keymap.set("n", "<leader>ii", ":PasteImage<cr>", { desc = "insert [i]mage from clipboard" })
		end,
	},

	{ -- preview equations
		"jbyuki/nabla.nvim",
		keys = {
			{ "<leader>qm", ':lua require"nabla".toggle_virt()<cr>', desc = "toggle [m]ath equations" },
		},
	},
	{ -- send code from python/r/qmd documets to a terminal or REPL
		-- like ipython, R, bash
		"jpalardy/vim-slime",
		dev = false,
		init = function()
			vim.b["quarto_is_python_chunk"] = false
			Quarto_is_in_python_chunk = function()
				require("otter.tools.functions").is_otter_language_context("python")
			end

			vim.cmd([[
      let g:slime_dispatch_ipython_pause = 100
      function SlimeOverride_EscapeText_quarto(text)
      call v:lua.Quarto_is_in_python_chunk()
      if exists('g:slime_python_ipython') && len(split(a:text,"\n")) > 1 && b:quarto_is_python_chunk && !(exists('b:quarto_is_r_mode') && b:quarto_is_r_mode)
      return [g:slime_dispatch_ipython_pause, a:text]
      else
      if exists('b:quarto_is_r_mode') && b:quarto_is_r_mode && b:quarto_is_python_chunk
      return [a:text, "\n"]
      else
      return [a:text]
      end
      end
      endfunction
      ]])

			vim.g.slime_target = "neovim"
			vim.g.slime_no_mappings = true
			-- vim.g.slime_python_ipython = 1
		end,
		config = function()
			vim.g.slime_input_pid = false
			vim.g.slime_suggest_default = true
			vim.g.slime_menu_config = false
			vim.g.slime_neovim_ignore_unlisted = true

			local function mark_terminal()
				local job_id = vim.b.terminal_job_id
				vim.print("job_id: " .. job_id)
			end

			local function set_terminal()
				vim.fn.call("slime#config", {})
			end
			vim.keymap.set("n", "<leader>qm", mark_terminal, { desc = "[m]ark otp terminal" })
			vim.keymap.set("n", "<leader>qs", set_terminal, { desc = "[s]et otp terminal" })
		end,
	},
}
