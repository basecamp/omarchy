-- Define terminal tag so themes and bindings can single terminals out. Omarchy
-- launches TUIs and its own terminal windows under dedicated app-ids
-- (org.omarchy.btop, org.omarchy.terminal, TUI.float, ...), so match those too.
o.window(
  "(Alacritty|kitty|com.mitchellh.ghostty|foot|wezterm|org\\.omarchy\\..*|TUI\\..*)",
  { tag = "+terminal" }
)
