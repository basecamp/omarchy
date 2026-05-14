-- Application bindings.
o.bind("SUPER + RETURN", "Terminal", "omarchy-launch-terminal")
o.bind("SUPER + ALT + RETURN", "Tmux", "omarchy-launch-terminal-tmux")
o.bind("SUPER + SHIFT + RETURN", "Browser", "omarchy-launch-browser")
o.bind("SUPER + SHIFT + F", "File manager", o.launch("nautilus --new-window"))
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", "omarchy-launch-nautilus-cwd")
o.bind("SUPER + SHIFT + B", "Browser", "omarchy-launch-browser")
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", "omarchy-launch-browser --private")
o.bind("SUPER + SHIFT + M", "Music", "omarchy-launch-or-focus spotify")
o.bind("SUPER + SHIFT + ALT + M", "Music TUI", "omarchy-launch-or-focus-tui cliamp")
o.bind("SUPER + SHIFT + N", "Editor", "omarchy-launch-editor")
o.bind("SUPER + SHIFT + D", "Docker", "omarchy-launch-tui lazydocker")
o.bind("SUPER + SHIFT + G", "Signal", [[omarchy-launch-or-focus ^signal$ "]] .. o.launch("signal-desktop") .. [["]])
o.bind("SUPER + SHIFT + O", "Obsidian", [[omarchy-launch-or-focus ^obsidian$ "]] .. o.launch("obsidian") .. [["]])
o.bind("SUPER + SHIFT + W", "Typora", o.launch("typora --enable-wayland-ime"))
o.bind("SUPER + SHIFT + SLASH", "Passwords", o.launch("1password"))

-- Web app bindings.
o.bind("SUPER + SHIFT + A", "ChatGPT", o.launch_webapp("https://chatgpt.com"))
o.bind("SUPER + SHIFT + ALT + A", "Grok", o.launch_webapp("https://grok.com"))
o.bind("SUPER + SHIFT + C", "Calendar", o.launch_webapp("https://app.hey.com/calendar/weeks/"))
o.bind("SUPER + SHIFT + E", "Email", o.launch_webapp("https://app.hey.com"))
o.bind("SUPER + SHIFT + Y", "YouTube", o.launch_webapp("https://youtube.com/"))
o.bind("SUPER + SHIFT + ALT + G", "WhatsApp", o.launch_webapp_sole("WhatsApp", "https://web.whatsapp.com/"))
o.bind("SUPER + SHIFT + CTRL + G", "Google Messages", o.launch_webapp_sole("Google Messages", "https://messages.google.com/web/conversations"))
o.bind("SUPER + SHIFT + P", "Google Photos", o.launch_webapp_sole("Google Photos", "https://photos.google.com/"))
o.bind("SUPER + SHIFT + X", "X", o.launch_webapp("https://x.com/"))
o.bind("SUPER + SHIFT + ALT + X", "X Post", o.launch_webapp("https://x.com/compose/post"))

-- Add extra bindings below.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Overwrite existing bindings with hl.unbind() first if needed.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-launch-walker -m symbols")
