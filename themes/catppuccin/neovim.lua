return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
      require("catppuccin").setup()

      local function brighten_borders()
        for _, group in ipairs({ "FloatBorder", "WinSeparator" }) do
          vim.api.nvim_set_hl(0, group, { fg = "#6c7086" })
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "catppuccin*",
        callback = brighten_borders,
      })

      brighten_borders()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
