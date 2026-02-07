return {
  -- required for the vantablack nvim theme
  {
    "bjarneo/aether.nvim",
    branch = "v2",
  },
  {
    "bjarneo/vantablack.nvim",
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vantablack",
    },
  },
}
