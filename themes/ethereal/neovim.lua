return {
  {
    "bjarneo/aether.nvim",
    name = "aether",
    priority = 1000,
    opts = {
      disable_italics = false,
      colors = {
        -- Monotone shades (base00-base07)
        base00 = "#060B1E", -- Default background
        base01 = "#6d7db6", -- Lighter background (status bars)
        base02 = "#060B1E", -- Selection background
        base03 = "#6d7db6", -- Comments, invisibles
        base04 = "#F99957", -- Dark foreground
        base05 = "#ffcead", -- Default foreground
        base06 = "#ffcead", -- Light foreground
        base07 = "#F99957", -- Light background

        -- Accent colors (base08-base0F)
        base08 = "#ED5B5A", -- Variables, errors, red
        base09 = "#faaaa9", -- Integers, constants, orange
        base0A = "#E9BB4F", -- Classes, types, yellow
        base0B = "#92a593", -- Strings, green
        base0C = "#a3bfd1", -- Support, regex, cyan
        base0D = "#7d82d9", -- Functions, keywords, blue
        base0E = "#c89dc1", -- Keywords, storage, magenta
        base0F = "#f7dc9c", -- Deprecated, brown/yellow
      },
    },
    config = function(_, opts)
      require("aether").setup(opts)
      vim.cmd.colorscheme("aether")

      -- Enable hot reload
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
