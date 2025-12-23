local screensaver = {}

function screensaver.apply_to_config(config)
  config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  }
end

return screensaver
