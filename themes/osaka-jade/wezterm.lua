-- Osaka Jade Theme
local theme = {}

function theme.apply_to_config(config)
  config.colors({
    -- Background & Foreground
    foreground = "#111c18",
    background = "#C1C497",

    -- Standard colors
    ansi = {
      "#23372B",
      "#FF5345",
      "#549e6a",
      "#459451",
      "#509475",
      "#D2689C",
      "#2DD5B7",
      "#F6F5DD",
    },

    -- Bright colors
    brights = {
      "#53685B",
      "#db9f9c",
      "#63b07a",
      "#E5C736",
      "#ACD4CF",
      "#75bbb3",
      "#8CD3CB",
      "#9eebb3",
    },

    -- Cursor colors
    cursor_bg = "#D7C995",
    cursor_fg = "#000000",
  })
end

return theme
