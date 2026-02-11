-- DedSec — Custom neovim colorscheme
-- Every color defined from our palette. base16-nvim is just the rendering engine.

return {
  {
    "RRethy/base16-nvim",
    lazy = false,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        require("base16-colorscheme").setup({
          base00 = "#050A0E", -- Default Background (near-black, cold blue)
          base01 = "#0A1018", -- Lighter Background (status bars, line numbers)
          base02 = "#1E3044", -- Selection Background (muted navy)
          base03 = "#1E3044", -- Comments, Invisibles
          base04 = "#94F0E0", -- Dark Foreground (status bars)
          base05 = "#B0F4E6", -- Default Foreground (main text)
          base06 = "#C8FFF4", -- Light Foreground (hover, highlight)
          base07 = "#C8FFF4", -- Lightest Foreground
          base08 = "#FF2D6F", -- Variables, Errors (DedSec hot magenta)
          base09 = "#BFFF00", -- Integers, Constants (acid green)
          base0A = "#E0FF66", -- Classes, Search (bright yellow-green)
          base0B = "#00FF41", -- Strings, Success (DedSec neon green)
          base0C = "#22D3EE", -- Support, Regex (electric cyan)
          base0D = "#00E5FF", -- Functions, Methods (DedSec cyan)
          base0E = "#A855F7", -- Keywords, Tags (DedSec purple)
          base0F = "#FF6B99", -- Deprecated, Embedded (soft magenta)
        })
      end,
    },
  },
}
