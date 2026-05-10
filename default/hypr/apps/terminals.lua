-- Define terminal tag to style them uniformly.
hl.window_rule({ match = { class = "(Alacritty|kitty|com.mitchellh.ghostty|foot)" }, tag = "+terminal" })
hl.window_rule({ match = { tag = "terminal" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "terminal" }, opacity = "0.97 0.9" })
