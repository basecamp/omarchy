return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg         = "{{ bg }}",
        dark_bg    = "{{ dark_bg }}",
        darker_bg  = "{{ darker_bg }}",
        lighter_bg = "{{ lighter_bg }}",

        fg         = "{{ fg }}",
        dark_fg    = "{{ dark_fg }}",
        light_fg   = "{{ light_fg }}",
        bright_fg  = "{{ bright_fg }}",
        muted      = "{{ muted }}",

        red        = "{{ red }}",
        yellow     = "{{ yellow }}",
        orange     = "{{ orange }}",
        green      = "{{ green }}",
        cyan       = "{{ cyan }}",
        blue       = "{{ blue }}",
        purple     = "{{ purple }}",
        brown      = "{{ brown }}",

        bright_red    = "{{ bright_red }}",
        bright_yellow = "{{ bright_yellow }}",
        bright_green  = "{{ bright_green }}",
        bright_cyan   = "{{ bright_cyan }}",
        bright_blue   = "{{ bright_blue }}",
        bright_purple = "{{ bright_purple }}",

        accent               = "{{ accent }}",
        cursor               = "{{ cursor }}",
        foreground           = "{{ foreground }}",
        background           = "{{ background }}",
        selection             = "{{ selection }}",
        selection_foreground = "{{ selection_foreground }}",
        selection_background = "{{ selection_background }}",
      },
    },
    -- set up hot reload
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
