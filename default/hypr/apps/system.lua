-- Floating windows.
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

o.window(
  "(org.omarchy.terminal|org.omarchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|Omarchy|About|TUI.float|imv|mpv)",
  {
    tag = "+floating-window",
  }
)

-- The portal only ever shows dialogs — file pickers, screen shares, permission
-- prompts — so every one of its windows belongs in the floating treatment,
-- whatever the app that asked for it titled it.
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- The About fastfetch layout needs more columns than the standard float provides.
-- This size only covers the first launch: omarchy-launch-about measures the
-- rendered content, remembers the size that hugs it, and applies that as its own
-- rule before every later launch.
o.window("org.omarchy.about", { float = true })
o.window("org.omarchy.about", { center = true })
o.window("org.omarchy.about", { size = { 920, 480 } })

-- btop refuses to draw at all below 80x24 characters. The standard float clears
-- that easily at the stock terminal font -- roughly 117x33 at foot's shipped 9pt
-- -- but the margin is spent as soon as the font is raised: 13pt on a 1.25-scaled
-- 1080p panel lands on exactly 80x24, and ghostty at 11pt on a 1.5-scaled one
-- comes up a column short at 79x24. Height is the constrained axis -- a 1280x720
-- logical screen has ~690 usable once the bar takes its cut -- while width has
-- room to spare, so this is sized to clear 80x24 with margin on both and still
-- fit the smallest screen.
o.window("org.omarchy.btop", { float = true })
o.window("org.omarchy.btop", { center = true })
o.window("org.omarchy.btop", { size = { 1040, 672 } })

o.window("dev.tensaku.Tensaku", { float = true })
o.window("dev.tensaku.Tensaku", { center = true })
o.window("omacalc", { float = true })

-- Fullscreen screensaver.
o.window("org.omarchy.screensaver", { fullscreen = true })
o.window("org.omarchy.screensaver", { float = true })
o.window("org.omarchy.screensaver", { animation = "slide" })

-- No transparency on media windows.
o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    tag = "-default-opacity",
  }
)
o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    opacity = "1 1",
  }
)

-- Popped window rounding.
o.window({ tag = "pop" }, { rounding = 8 })

-- Prevent idle while open.
o.window({ tag = "noidle" }, { idle_inhibit = "always" })
