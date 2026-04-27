--
-- Flat searchable list of all Omarchy Menu actions for Elephant/Walker
-- Activate with the ">" prefix in Walker
--
Name = "omarchymenusearch"
NamePretty = "Omarchy Menu Search"
HideFromProviderlist = true

function GetEntries()
  local entries = {}

  -- Detect best Ollama package for this machine's GPU
  local ollama_pkg = "ollama"
  local h = io.popen("command -v nvidia-smi 2>/dev/null")
  if h then
    local out = h:read("*l"); h:close()
    if out and out ~= "" then
      ollama_pkg = "ollama-cuda"
    else
      h = io.popen("command -v rocminfo 2>/dev/null")
      if h then
        out = h:read("*l"); h:close()
        if out and out ~= "" then ollama_pkg = "ollama-rocm" end
      end
    end
  end

  local function add(text, path, cmd)
    table.insert(entries, {
      Text = text .. "  ",
      Subtext = path,
      Actions = {
        activate = cmd,
      },
    })
  end

  local function add_terminal(text, path, cmd)
    table.insert(entries, {
      Text = text .. "  ",
      Subtext = path,
      Actions = {
        activate = "omarchy-launch-floating-terminal-with-presentation " .. cmd,
      },
    })
  end

  -- Learn
  add("Keybindings",           "Learn",                    "omarchy-menu-keybindings")
  add("Omarchy Manual",        "Learn",                    'omarchy-launch-webapp "https://learn.omacom.io/2/the-omarchy-manual"')
  add("Hyprland Wiki",         "Learn",                    'omarchy-launch-webapp "https://wiki.hypr.land/"')
  add("Arch Wiki",             "Learn",                    'omarchy-launch-webapp "https://wiki.archlinux.org/title/Main_page"')
  add("Bash Cheatsheet",       "Learn",                    'omarchy-launch-webapp "https://devhints.io/bash"')
  add("Neovim Keymaps",        "Learn",                    'omarchy-launch-webapp "https://www.lazyvim.org/keymaps"')

  -- Trigger → Capture
  add("Screenshot",            "Trigger → Capture",        "omarchy-cmd-screenshot")
  add("Screenrecord (no audio)",              "Trigger → Capture → Screenrecord", "omarchy-cmd-screenrecord")
  add("Screenrecord (desktop audio)",         "Trigger → Capture → Screenrecord", "omarchy-cmd-screenrecord --with-desktop-audio")
  add("Screenrecord (desktop + mic)",         "Trigger → Capture → Screenrecord", "omarchy-cmd-screenrecord --with-desktop-audio --with-microphone-audio")
  add("Color Picker",          "Trigger → Capture",        "pkill hyprpicker || hyprpicker -a")

  -- Trigger → Share
  add("Share Clipboard",       "Trigger → Share",          "omarchy-cmd-share clipboard")
  add_terminal("Share File",   "Trigger → Share",          "bash -c 'omarchy-cmd-share file'")
  add_terminal("Share Folder", "Trigger → Share",          "bash -c 'omarchy-cmd-share folder'")

  -- Trigger → Toggle
  add("Toggle Screensaver",        "Trigger → Toggle",     "omarchy-toggle-screensaver")
  add("Toggle Nightlight",         "Trigger → Toggle",     "omarchy-toggle-nightlight")
  add("Toggle Idle Lock",          "Trigger → Toggle",     "omarchy-toggle-idle")
  add("Toggle Top Bar",            "Trigger → Toggle",     "omarchy-toggle-waybar")
  add("Toggle Workspace Layout",   "Trigger → Toggle",     "omarchy-hyprland-workspace-layout-toggle")
  add("Toggle Window Gaps",        "Trigger → Toggle",     "omarchy-hyprland-window-gaps-toggle")
  add("Toggle 1-Window Ratio",     "Trigger → Toggle",     "omarchy-hyprland-window-single-square-aspect-toggle")
  add("Toggle Display Scaling",    "Trigger → Toggle",     "omarchy-hyprland-monitor-scaling-cycle")

  -- Trigger → Hardware
  add_terminal("Toggle Hybrid GPU", "Trigger → Hardware",  "omarchy-toggle-hybrid-gpu")

  -- Style
  add("Theme",                 "Style",                    "omarchy-launch-walker -m menus:omarchythemes --width 800 --minheight 400")
  add("Font",                  "Style",                    "omarchy-menu font")
  add("Background",            "Style",                    "omarchy-launch-walker -m menus:omarchyBackgroundSelector --width 800 --minheight 400")
  add("Hyprland Look & Feel",  "Style",                    "omarchy-launch-editor ~/.config/hypr/looknfeel.conf")
  add("Screensaver Text",      "Style",                    "omarchy-launch-editor ~/.config/omarchy/branding/screensaver.txt")
  add("About Text",            "Style",                    "omarchy-launch-editor ~/.config/omarchy/branding/about.txt")

  -- Setup
  add("Audio",                 "Setup",                    "omarchy-launch-audio")
  add("Wifi",                  "Setup",                    "omarchy-launch-wifi")
  add("Bluetooth",             "Setup",                    "omarchy-launch-bluetooth")
  add_terminal("DNS",          "Setup",                    "omarchy-setup-dns")
  add_terminal("Fingerprint",  "Setup → Security",         "omarchy-setup-fingerprint")
  add_terminal("Fido2",        "Setup → Security",         "omarchy-setup-fido2")

  -- Setup → Config
  add("Config: Hyprland",      "Setup → Config",           "omarchy-launch-editor ~/.config/hypr/hyprland.conf")
  add("Config: Walker",        "Setup → Config",           "omarchy-launch-editor ~/.config/walker/config.toml && omarchy-restart-walker")
  add("Config: Waybar",        "Setup → Config",           "omarchy-launch-editor ~/.config/waybar/config.jsonc && omarchy-restart-waybar")
  add("Config: Hypridle",      "Setup → Config",           "omarchy-launch-editor ~/.config/hypr/hypridle.conf && omarchy-restart-hypridle")
  add("Config: Hyprlock",      "Setup → Config",           "omarchy-launch-editor ~/.config/hypr/hyprlock.conf")
  add("Config: Hyprsunset",    "Setup → Config",           "omarchy-launch-editor ~/.config/hypr/hyprsunset.conf && omarchy-restart-hyprsunset")
  add("Config: Swayosd",       "Setup → Config",           "omarchy-launch-editor ~/.config/swayosd/config.toml && omarchy-restart-swayosd")
  add("Config: XCompose",      "Setup → Config",           "omarchy-launch-editor ~/.XCompose && omarchy-restart-xcompose")

  -- Install → Service
  add_terminal("Install Dropbox",          "Install → Service",    "omarchy-install-dropbox")
  add_terminal("Install Tailscale",        "Install → Service",    "omarchy-install-tailscale")
  add_terminal("Install NordVPN",          "Install → Service",    "omarchy-install-nordvpn")
  add_terminal("Install Chromium Account", "Install → Service",    "omarchy-install-chromium-google-account")

  -- Install → AI
  add_terminal("Install Dictation",    "Install → AI",     "omarchy-voxtype-install")
  add_terminal("Install Claude Code",  "Install → AI",     "echo 'Installing Claude Code...'; omarchy-pkg-add claude-code")
  add_terminal("Install Codex",        "Install → AI",     "echo 'Installing Codex...'; omarchy-pkg-add openai-codex")
  add_terminal("Install Gemini CLI",   "Install → AI",     "echo 'Installing Gemini CLI...'; omarchy-pkg-add gemini-cli")
  add_terminal("Install Copilot CLI",  "Install → AI",     "echo 'Installing Copilot CLI...'; omarchy-pkg-add github-copilot-cli")
  add_terminal("Install Cursor CLI",   "Install → AI",     "echo 'Installing Cursor CLI...'; omarchy-pkg-add cursor-cli")
  add_terminal("Install LM Studio",    "Install → AI",     "echo 'Installing LM Studio...'; omarchy-pkg-add lmstudio-bin")
  add_terminal("Install Ollama",       "Install → AI",     "echo 'Installing Ollama...'; omarchy-pkg-add " .. ollama_pkg)
  add_terminal("Install Crush",        "Install → AI",     "echo 'Installing Crush...'; omarchy-pkg-add crush-bin")

  -- Install → Editor
  add_terminal("Install VSCode",        "Install → Editor", "omarchy-install-vscode")
  add_terminal("Install Cursor",        "Install → Editor", "echo 'Installing Cursor...'; omarchy-pkg-add cursor-bin && setsid gtk-launch cursor")
  add_terminal("Install Zed",           "Install → Editor", "echo 'Installing Zed...'; omarchy-pkg-add zed && setsid gtk-launch dev.zed.Zed")
  add_terminal("Install Sublime Text",  "Install → Editor", "echo 'Installing Sublime Text...'; omarchy-pkg-add sublime-text-4 && setsid gtk-launch sublime_text")
  add_terminal("Install Helix",         "Install → Editor", "echo 'Installing Helix...'; omarchy-pkg-add helix")
  add_terminal("Install Emacs",         "Install → Editor", "echo 'Installing Emacs...'; omarchy-pkg-add emacs-wayland")

  -- Install → Terminal
  add_terminal("Install Alacritty",    "Install → Terminal", "omarchy-install-terminal alacritty")
  add_terminal("Install Ghostty",      "Install → Terminal", "omarchy-install-terminal ghostty")
  add_terminal("Install Kitty",        "Install → Terminal", "omarchy-install-terminal kitty")

  -- Install → Gaming
  add_terminal("Install Steam",           "Install → Gaming", "omarchy-install-steam")
  add_terminal("Install GeForce NOW",     "Install → Gaming", "omarchy-install-geforce-now")
  add_terminal("Install Minecraft",       "Install → Gaming", "echo 'Installing Minecraft...'; omarchy-pkg-add minecraft-launcher && setsid gtk-launch minecraft-launcher")
  add_terminal("Install Xbox Controller", "Install → Gaming", "omarchy-install-xbox-controllers")

  -- Install → Style
  add_terminal("Install Theme",      "Install → Style",  "omarchy-theme-install")
  add_terminal("Install Font: Cascadia Mono",  "Install → Style → Font", "echo 'Installing Cascadia Mono...'; omarchy-pkg-add ttf-cascadia-mono-nerd && sleep 2 && omarchy-font-set 'CaskaydiaMono Nerd Font'")
  add_terminal("Install Font: Meslo LG Mono",  "Install → Style → Font", "echo 'Installing Meslo LG Mono...'; omarchy-pkg-add ttf-meslo-nerd && sleep 2 && omarchy-font-set 'MesloLGL Nerd Font'")
  add_terminal("Install Font: Fira Code",      "Install → Style → Font", "echo 'Installing Fira Code...'; omarchy-pkg-add ttf-firacode-nerd && sleep 2 && omarchy-font-set 'FiraCode Nerd Font'")
  add_terminal("Install Font: Victor Mono",    "Install → Style → Font", "echo 'Installing Victor Mono...'; omarchy-pkg-add ttf-victor-mono-nerd && sleep 2 && omarchy-font-set 'VictorMono Nerd Font'")
  add_terminal("Install Font: Bitstream Vera", "Install → Style → Font", "echo 'Installing Bitstream Vera...'; omarchy-pkg-add ttf-bitstream-vera-mono-nerd && sleep 2 && omarchy-font-set 'BitstromWera Nerd Font'")
  add_terminal("Install Font: Iosevka",        "Install → Style → Font", "echo 'Installing Iosevka...'; omarchy-pkg-add ttf-iosevka-nerd && sleep 2 && omarchy-font-set 'Iosevka Nerd Font Mono'")

  -- Install → Development
  add_terminal("Install Docker DBs",       "Install → Development", "omarchy-install-docker-dbs")
  add_terminal("Install Ruby on Rails",    "Install → Development", "omarchy-install-dev-env ruby")
  add_terminal("Install Node.js",          "Install → Development", "omarchy-install-dev-env node")
  add_terminal("Install Bun",              "Install → Development", "omarchy-install-dev-env bun")
  add_terminal("Install Deno",             "Install → Development", "omarchy-install-dev-env deno")
  add_terminal("Install Go",               "Install → Development", "omarchy-install-dev-env go")
  add_terminal("Install PHP",              "Install → Development", "omarchy-install-dev-env php")
  add_terminal("Install Laravel",          "Install → Development", "omarchy-install-dev-env laravel")
  add_terminal("Install Symfony",          "Install → Development", "omarchy-install-dev-env symfony")
  add_terminal("Install Python",           "Install → Development", "omarchy-install-dev-env python")
  add_terminal("Install Elixir",           "Install → Development", "omarchy-install-dev-env elixir")
  add_terminal("Install Phoenix",          "Install → Development", "omarchy-install-dev-env phoenix")
  add_terminal("Install Zig",              "Install → Development", "omarchy-install-dev-env zig")
  add_terminal("Install Rust",             "Install → Development", "omarchy-install-dev-env rust")
  add_terminal("Install Java",             "Install → Development", "omarchy-install-dev-env java")
  add_terminal("Install .NET",             "Install → Development", "omarchy-install-dev-env dotnet")
  add_terminal("Install OCaml",            "Install → Development", "omarchy-install-dev-env ocaml")
  add_terminal("Install Clojure",          "Install → Development", "omarchy-install-dev-env clojure")
  add_terminal("Install Scala",            "Install → Development", "omarchy-install-dev-env scala")

  -- Remove
  add_terminal("Remove Web App",       "Remove",           "omarchy-webapp-remove")
  add_terminal("Remove TUI",           "Remove",           "omarchy-tui-remove")
  add_terminal("Remove Ruby on Rails", "Remove → Dev Env", "omarchy-remove-dev-env ruby")
  add_terminal("Remove Node.js",       "Remove → Dev Env", "omarchy-remove-dev-env node")
  add_terminal("Remove Bun",           "Remove → Dev Env", "omarchy-remove-dev-env bun")
  add_terminal("Remove Deno",          "Remove → Dev Env", "omarchy-remove-dev-env deno")
  add_terminal("Remove Go",            "Remove → Dev Env", "omarchy-remove-dev-env go")
  add_terminal("Remove PHP",           "Remove → Dev Env", "omarchy-remove-dev-env php")
  add_terminal("Remove Laravel",       "Remove → Dev Env", "omarchy-remove-dev-env laravel")
  add_terminal("Remove Symfony",       "Remove → Dev Env", "omarchy-remove-dev-env symfony")
  add_terminal("Remove Python",        "Remove → Dev Env", "omarchy-remove-dev-env python")
  add_terminal("Remove Elixir",        "Remove → Dev Env", "omarchy-remove-dev-env elixir")
  add_terminal("Remove Phoenix",       "Remove → Dev Env", "omarchy-remove-dev-env phoenix")
  add_terminal("Remove Zig",           "Remove → Dev Env", "omarchy-remove-dev-env zig")
  add_terminal("Remove Rust",          "Remove → Dev Env", "omarchy-remove-dev-env rust")
  add_terminal("Remove Java",          "Remove → Dev Env", "omarchy-remove-dev-env java")
  add_terminal("Remove .NET",          "Remove → Dev Env", "omarchy-remove-dev-env dotnet")
  add_terminal("Remove OCaml",         "Remove → Dev Env", "omarchy-remove-dev-env ocaml")
  add_terminal("Remove Clojure",       "Remove → Dev Env", "omarchy-remove-dev-env clojure")
  add_terminal("Remove Scala",         "Remove → Dev Env", "omarchy-remove-dev-env scala")
  add_terminal("Remove Preinstalls",   "Remove",           "omarchy-remove-preinstalls")
  add_terminal("Remove Dictation",     "Remove",           "omarchy-voxtype-remove")
  add_terminal("Remove Theme",         "Remove",           "omarchy-theme-remove")
  add_terminal("Remove Windows VM",    "Remove",           "omarchy-windows-vm remove")
  add_terminal("Remove Fingerprint",   "Remove",           "omarchy-setup-fingerprint --remove")
  add_terminal("Remove Fido2",         "Remove",           "omarchy-setup-fido2 --remove")

  -- Update
  add_terminal("Update Omarchy",       "Update",           "omarchy-update")
  add_terminal("Update Extra Themes",  "Update",           "omarchy-theme-update")
  add_terminal("Update Firmware",      "Update",           "omarchy-update-firmware")
  add_terminal("Update Timezone",      "Update",           "omarchy-tz-select")
  add("Restart Walker",                "Update → Process", "omarchy-restart-walker")
  add("Restart Waybar",                "Update → Process", "omarchy-restart-waybar")
  add_terminal("Restart Audio",        "Update → Hardware", "omarchy-restart-pipewire")
  add_terminal("Restart Wi-Fi",        "Update → Hardware", "omarchy-restart-wifi")
  add_terminal("Restart Bluetooth",    "Update → Hardware", "omarchy-restart-bluetooth")

  -- System
  add("Screensaver",           "System",                   "omarchy-launch-screensaver force")
  add("Lock Screen",           "System",                   "omarchy-lock-screen")
  add("Suspend",               "System",                   "systemctl suspend")
  add("Logout",                "System",                   "omarchy-system-logout")
  add("Restart",               "System",                   "omarchy-system-reboot")
  add("Shutdown",              "System",                   "omarchy-system-shutdown")

  return entries
end
