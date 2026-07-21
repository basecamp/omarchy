-- Define terminal tag to style them uniformly.
o.window("(Alacritty|kitty|com.mitchellh.ghostty|foot|wezterm)", { tag = "+terminal" })
o.window({ tag = "terminal" }, { tag = "-default-opacity", opacity = "0.985 0.95" })
