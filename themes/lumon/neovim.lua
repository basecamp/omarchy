return {
  {
    "bjarneo/aether.nvim",
    branch = "v2",
    name = "aether",
    priority = 1000,
    opts = {
      transparent = false,
      colors = {
        -- Background colors
        bg = "#1b2d40",
        bg_dark = "#16242d",
        bg_highlight = "#355066",

        -- Foreground colors
        -- fg: Object properties, builtin types, builtin variables, member access, default text
        fg = "#c7d2de",
        -- fg_dark: Inactive elements, statusline, secondary text
        fg_dark = "#c7d2de",
        -- comment: Line highlight, gutter elements, disabled states
        comment = "#355066",

        -- Accent colors
        -- red: Errors, diagnostics, tags, deletions, breakpoints
        red = "#6e9fca",
        -- orange: Constants, numbers, current line number, git modifications
        orange = "#8fb9dc",
        -- yellow: Types, classes, constructors, warnings, numbers, booleans
        yellow = "#86b6da",
        -- green: Comments, strings, success states, git additions
        green = "#79abd2",
        -- cyan: Parameters, regex, preprocessor, hints, properties
        cyan = "#b5deef",
        -- blue: Functions, keywords, directories, links, info diagnostics
        blue = "#92c7e7",
        -- purple: Storage keywords, special keywords, identifiers, namespaces
        purple = "#9fcfe9",
        -- magenta: Function declarations, exception handling, tags
        magenta = "#b3d7ec",
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
