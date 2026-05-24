return {
  {
    "bjarneo/aether.nvim",
    branch = "v2",
    name = "aether",
    priority = 1000,
    opts = {
      transparent = false,
      colors = {
  bg           = "#0c0b0c",
  bg_dark      = "#0c0b0c",
  bg_highlight = "#716661",     -- still only change to bg_highlight

  -- Foregrounds
  fg           = "#f1f1ef",
  fg_dark      = "#e0dbd9",
  comment      = "#94918c",

  red          = "#e36a58",
  orange       = "#c38d72",
  yellow       = "#c8a88a",
  green        = "#a4dded",
  cyan         = "#725379",
  blue         = "#4691a1",
  purple       = "#c9a3c9",
  magenta      = "#b9a0d1",
      },
    },
    config = function(_, opts)
      require("aether").setup(opts)
      vim.cmd.colorscheme("aether")
      require("aether.hotreload").setup()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}