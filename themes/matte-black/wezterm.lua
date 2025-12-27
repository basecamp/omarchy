-- Matte-Black Theme
local theme = {}

function theme.apply_to_config(config)
  config.colors({
    -- Background & Foreground
    foreground = "#bebebe",
    background = "#121212",

    -- Standard colors
    ansi = {
      "#333333",
      "#D35F5F",
      "#FFC107",
      "#b91c1c",
      "#e68e0d",
      "#D35F5F",
      "#bebebe",
      "#bebebe",
    },

    -- Bright colors
    brights = {
      "#8a8a8d",
      "#B91C1C",
      "#FFC107",
      "#b90a0a",
      "#f59e0b",
      "#B91C1C",
      "#eaeaea",
      "#ffffff",
    },

    -- Cursor colors
    cursor_bg = "#eaeaea",
    cursor_fg = "#121212",

    -- Selection colors
    selection_fg = "#bebebe",
    selection_bg = "#333333",
  })
end

return theme
