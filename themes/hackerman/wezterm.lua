-- Hackerman Theme
local theme = {}

function theme.apply_to_config(config)
  config.colors({
    -- Background & Foreground
    foreground = "#ddf7ff",
    background = "#0B0C16",

    -- Standard colors
    ansi = {
      "#0B0C16",
      "#50f872",
      "#4fe88f",
      "#50f7d4",
      "#829dd4",
      "#86a7df",
      "#7cf8f7",
      "#85E1FB",
    },

    -- Bright colors
    brights = {
      "#6a6e95",
      "#85ff9d",
      "#9cf7c2",
      "#a4ffec",
      "#c4d2ed",
      "#cddbf4",
      "#d1fffe",
      "#ddf7ff",
    },

    -- Cursor colors
    cursor_bg = "#ddf7ff",
    cursor_fg = "#0B0C16",
  })
end

return theme
