return {
  {
    "bjarneo/aether.nvim",
    name = "aether",
    priority = 1000,
    opts = {
      disable_italics = false,
      colors = {
        -- Monotone shades (base00-base07)
        base00 = "#0B0C16", -- Default background
        base01 = "#6a6e95", -- Lighter background (status bars)
        base02 = "#0B0C16", -- Selection background
        base03 = "#6a6e95", -- Comments, invisibles
        base04 = "#85E1FB", -- Dark foreground
        base05 = "#ddf7ff", -- Default foreground
        base06 = "#ddf7ff", -- Light foreground
        base07 = "#85E1FB", -- Light background

        -- Accent colors (base08-base0F)
        base08 = "#50f872", -- Variables, errors, red
        base09 = "#85ff9d", -- Integers, constants, orange
        base0A = "#50f7d4", -- Classes, types, yellow
        base0B = "#4fe88f", -- Strings, green
        base0C = "#7cf8f7", -- Support, regex, cyan
        base0D = "#829dd4", -- Functions, keywords, blue
        base0E = "#86a7df", -- Keywords, storage, magenta
        base0F = "#a4ffec", -- Deprecated, brown/yellow
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
