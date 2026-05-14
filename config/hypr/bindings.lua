-- Application bindings.
o.bind("SUPER + RETURN", "Terminal", "omarchy-launch-terminal")
o.bind("SUPER + ALT + RETURN", "Tmux", "omarchy-launch-terminal-tmux")
o.bind("SUPER + SHIFT + RETURN", "Browser", "omarchy-launch-browser")
o.bind_launch("SUPER + SHIFT + F", "File manager", "nautilus --new-window")
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", "omarchy-launch-nautilus-cwd")
o.bind("SUPER + SHIFT + B", "Browser", "omarchy-launch-browser")
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", "omarchy-launch-browser --private")
o.bind("SUPER + SHIFT + M", "Music", "omarchy-launch-or-focus spotify")
o.bind("SUPER + SHIFT + ALT + M", "Music TUI", "omarchy-launch-or-focus-tui cliamp")
o.bind("SUPER + SHIFT + N", "Editor", "omarchy-launch-editor")
o.bind("SUPER + SHIFT + D", "Docker", "omarchy-launch-tui lazydocker")
o.bind_sole("SUPER + SHIFT + G", "Signal", "^signal$", "signal-desktop")
o.bind_sole("SUPER + SHIFT + O", "Obsidian", "^obsidian$", "obsidian")
o.bind_launch("SUPER + SHIFT + W", "Typora", "typora --enable-wayland-ime")
o.bind_launch("SUPER + SHIFT + SLASH", "Passwords", "1password")

-- Web app bindings.
o.bind_webapp("SUPER + SHIFT + A", "ChatGPT", "https://chatgpt.com")
o.bind_webapp("SUPER + SHIFT + ALT + A", "Grok", "https://grok.com")
o.bind_webapp("SUPER + SHIFT + C", "Calendar", "https://app.hey.com/calendar/weeks/")
o.bind_webapp("SUPER + SHIFT + E", "Email", "https://app.hey.com")
o.bind_webapp("SUPER + SHIFT + Y", "YouTube", "https://youtube.com/")
o.bind_webapp_sole("SUPER + SHIFT + ALT + G", "WhatsApp", "https://web.whatsapp.com/")
o.bind_webapp_sole("SUPER + SHIFT + CTRL + G", "Google Messages", "https://messages.google.com/web/conversations")
o.bind_webapp_sole("SUPER + SHIFT + P", "Google Photos", "https://photos.google.com/")
o.bind_webapp("SUPER + SHIFT + X", "X", "https://x.com/")
o.bind_webapp("SUPER + SHIFT + ALT + X", "X Post", "https://x.com/compose/post")

-- Add extra bindings below.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Overwrite existing bindings with hl.unbind() first if needed.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-launch-walker -m symbols")
