OMARCHY_DESCRIPTION="Webapps"

omarchy_install() {
  omarchy-webapp-install "HEY" https://app.hey.com HEY.png
  omarchy-webapp-install "Basecamp" https://launchpad.37signals.com Basecamp.png
  omarchy-webapp-install "WhatsApp" https://web.whatsapp.com/ WhatsApp.png
  omarchy-webapp-install "Google Photos" https://photos.google.com/ "Google Photos.png"
  omarchy-webapp-install "Google Contacts" https://contacts.google.com/ "Google Contacts.png"
  omarchy-webapp-install "Google Messages" https://messages.google.com/web/conversations "Google Messages.png"
  omarchy-webapp-install "ChatGPT" https://chatgpt.com/ ChatGPT.png
  omarchy-webapp-install "YouTube" https://youtube.com/ YouTube.png
  omarchy-webapp-install "GitHub" https://github.com/ GitHub.png
  omarchy-webapp-install "X" https://x.com/ X.png
  omarchy-webapp-install "Figma" https://figma.com/ Figma.png
  omarchy-webapp-install "Discord" https://discord.com/channels/@me Discord.png
  omarchy-webapp-install "Zoom" https://app.zoom.us/wc/home Zoom.png "omarchy-webapp-handler-zoom %u" "x-scheme-handler/zoommtg;x-scheme-handler/zoomus"
}

omarchy_verify() {
  # Check all webapps - use warnings since these are optional
  [[ -f "$HOME/.local/share/applications/HEY.desktop" ]] || add_warning "HEY webapp not installed"
  [[ -f "$HOME/.local/share/applications/Basecamp.desktop" ]] || add_warning "Basecamp webapp not installed"
  [[ -f "$HOME/.local/share/applications/WhatsApp.desktop" ]] || add_warning "WhatsApp webapp not installed"
  [[ -f "$HOME/.local/share/applications/Google Photos.desktop" ]] || add_warning "Google Photos webapp not installed"
  [[ -f "$HOME/.local/share/applications/Google Contacts.desktop" ]] || add_warning "Google Contacts webapp not installed"
  [[ -f "$HOME/.local/share/applications/Google Messages.desktop" ]] || add_warning "Google Messages webapp not installed"
  [[ -f "$HOME/.local/share/applications/ChatGPT.desktop" ]] || add_warning "ChatGPT webapp not installed"
  [[ -f "$HOME/.local/share/applications/YouTube.desktop" ]] || add_warning "YouTube webapp not installed"
  [[ -f "$HOME/.local/share/applications/GitHub.desktop" ]] || add_warning "GitHub webapp not installed"
  [[ -f "$HOME/.local/share/applications/X.desktop" ]] || add_warning "X webapp not installed"
  [[ -f "$HOME/.local/share/applications/Figma.desktop" ]] || add_warning "Figma webapp not installed"
  [[ -f "$HOME/.local/share/applications/Discord.desktop" ]] || add_warning "Discord webapp not installed"
  [[ -f "$HOME/.local/share/applications/Zoom.desktop" ]] || add_warning "Zoom webapp not installed"
}
