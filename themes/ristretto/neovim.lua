return {
  {
    "gthelding/monokai-pro.nvim",
    config = function()
      require("monokai-pro").setup({
        filter = "ristretto",
        override = function()
          return {
            NonText = { fg = "#948a8b" },
            MiniIconsGrey = { fg = "#948a8b" },
	    MiniIconsRed = { fg = "#fd6883" },
	    MiniIconsBlue = { fg = "#85dacc" },
	    MiniIconsGreen = { fg = "#adda78" },
	    MiniIconsYellow = { fg = "#f9cc6c" },
	    MiniIconsOrange = { fg = "#f38d70" },
	    MiniIconsPurple = { fg = "#a8a9eb" },
	    MiniIconsAzure = { fg = "#a8a9eb" },
	    MiniIconsCyan = { fg = "#85dacc" }, -- same value as MiniIconsBlue for consistency
          }
        end,
      })
      vim.cmd([[colorscheme monokai-pro]])
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-pro",
    },
  },
}
