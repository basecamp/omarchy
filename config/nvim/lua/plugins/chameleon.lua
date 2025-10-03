return {
  {
    "tahayvr/chameleon.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("chameleon").setup({
        system = {
          symlink_path = vim.fn.expand("~/.config/omarchy/current/theme"),
          debounce_ms = 100,
          notify = false,
        },
      })
    end,
  },
}