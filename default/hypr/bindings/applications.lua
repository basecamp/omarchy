-- Essential application bindings.
o.bind(omarchy_bindings.terminal, "Terminal", { omarchy = "terminal" })
o.bind(omarchy_bindings.browser, "Browser", { omarchy = "browser" })
o.bind(omarchy_bindings.file_manager, "File manager", { omarchy = "nautilus" })
o.bind(omarchy_bindings.file_manager_cwd, "File manager (cwd)", { omarchy = "nautilus-cwd" })
o.bind(omarchy_bindings.browser_1, "Browser", { omarchy = "browser" })
o.bind(omarchy_bindings.browser_private, "Browser (private)", { omarchy = "browser --private" })
o.bind(omarchy_bindings.editor, "Editor", { omarchy = "editor" })

if o.preinstalled_bindings_enabled() then
  -- Bindings for preinstalled Omarchy applications, TUIs, and web apps.
  o.bind(omarchy_bindings.tmux, "Tmux", { omarchy = "terminal-tmux" })
  o.bind(omarchy_bindings.herdr, "Herdr", { omarchy = "terminal-herdr" })
  o.bind(omarchy_bindings.music, "Music", { omarchy = "spotify" })
  o.bind(omarchy_bindings.music_tui, "Music TUI", { tui = "cliamp", focus = true })
  o.bind(omarchy_bindings.docker, "Docker", { tui = "lazydocker" })
  o.bind(omarchy_bindings.signal, "Signal", { omarchy = "signal" })
  o.bind(omarchy_bindings.obsidian, "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
  o.bind(omarchy_bindings.omawrite, "Omawrite", { launch = "omawrite" })
  o.bind(omarchy_bindings.passwords, "Passwords", { omarchy = "1password" })

  o.bind(omarchy_bindings.chatgpt, "ChatGPT", { webapp = "https://chatgpt.com" })
  o.bind(omarchy_bindings.grok, "Grok", { webapp = "https://grok.com" })
  o.bind(omarchy_bindings.calendar, "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })
  o.bind(omarchy_bindings.email, "Email", { webapp = "https://app.hey.com" })
  o.bind(omarchy_bindings.new_email, "New email", { webapp = "https://app.hey.com/messages/new?display=standalone&new_window=true" })
  o.bind(omarchy_bindings.youtube, "YouTube", { webapp = "https://youtube.com/" })
  o.bind(omarchy_bindings.whatsapp, "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })
  o.bind(omarchy_bindings.google_messages, "Google Messages", { webapp = "https://messages.google.com/web/conversations", focus = true })
  o.bind(omarchy_bindings.google_photos, "Google Photos", { webapp = "https://photos.google.com/", focus = true })
  o.bind(omarchy_bindings.google_maps, "Google Maps", { webapp = "https://maps.google.com/", focus = true })
  o.bind(omarchy_bindings.x, "X", { webapp = "https://x.com/" })
  o.bind(omarchy_bindings.x_post, "X Post", { webapp = "https://x.com/compose/post" })
end
