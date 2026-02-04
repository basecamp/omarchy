#!/bin/bash

if [ -z "$AUTARKY_BARE" ]; then
  source ~/.local/share/autarky/default/zsh/functions
  web2app "WhatsApp" https://web.whatsapp.com/ https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/whatsapp.png
  web2app "ChatGPT" https://chatgpt.com/ https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/chatgpt.png
  web2app "YouTube" https://youtube.com/ https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/youtube.png
  web2app "GitHub" https://github.com/ https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/github-light.png
  web2app "ProtonCalendar" https://calendar.proton.me/ https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proton-calendar.png 
  web2app "APOD" https://apod.nasa.gov/apod/ https://cdn.jsdelivr.net/npm/simple-icons@15.16.0/icons/saturn.svg
fi
