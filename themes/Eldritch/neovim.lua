return {
    {
        "bjarneo/aether.nvim",
        name = "aether",
        priority = 1000,
        opts = {
            disable_italics = false,
            colors = {
                -- Monotone shades (base00-base07)
                base00 = "#212337", -- Default background
                base01 = "#37f499", -- Lighter background (status bars)
                base02 = "#212337", -- Selection background
                base03 = "#37f499", -- Comments, invisibles
                base04 = "#f265b5", -- Dark foreground
                base05 = "#37f499", -- Default foreground
                base06 = "#37f499", -- Light foreground
                base07 = "#f265b5", -- Light background

                -- Accent colors (base08-base0F)
                base08 = "#37f499", -- Variables, errors, red
                base09 = "#f16c75", -- Integers, constants, orange
                base0A = "#f265b5", -- Classes, types, yellow
                base0B = "#04d1f9", -- Strings, green
                base0C = "#7081d0", -- Support, regex, cyan
                base0D = "#7081d0", -- Functions, keywords, blue
                base0E = "#04d1f9", -- Keywords, storage, magenta
                base0F = "#ebfafa", -- Deprecated, brown/yellow
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
