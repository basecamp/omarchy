-- Define terminal tag so themes and bindings can single terminals out. Omarchy
-- launches TUIs and its own terminal windows under dedicated app-ids
-- (org.omarchy.btop, org.omarchy.terminal, TUI.float, ...), so match those too.
-- The class is matched in full, so foot's other app-id needs spelling out.
o.window(
  "(Alacritty|kitty|com.mitchellh.ghostty|foot|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.omarchy\\..*|TUI\\..*)",
  { tag = "+terminal" }
)
