-- Ethereal Theme
local theme = {}

function theme.apply_to_config(config)
  config.colors({
    -- Background & Foreground
    foreground = "#ffcead",
    background = "#060B1E",

    -- Standard colors
    ansi = {
      "#060B1E",
      "#ED5B5A",
      "#92a593",
      "#E9BB4F",
      "#7d82d9",
      "#c89dc1",
      "#a3bfd1",
      "#F99957",
    },

    -- Bright colors
    brights = {
      "#6d7db6",
      "#faaaa9",
      "#c4cfc4",
      "#f7dc9c",
      "#c2c4f0",
      "#ead7e7",
      "#dfeaf0",
      "#ffcead",
    },

    -- Cursor colors
    cursor_bg = "#ffcead",
    cursor_fg = "#060B1E",
  })
end

return theme
