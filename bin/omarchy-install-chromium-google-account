#!/bin/bash

if [[ -f ~/.config/chromium-flags.conf ]]; then
  CONF=~/.config/chromium-flags.conf

  grep -qxF -- "--oauth2-client-id=77185425430.apps.googleusercontent.com" "$CONF" ||
    echo "--oauth2-client-id=77185425430.apps.googleusercontent.com" >>"$CONF"

  grep -qxF -- "--oauth2-client-secret=OTJgUOQcT7lO7GsGZq2G4IlT" "$CONF" ||
    echo "--oauth2-client-secret=OTJgUOQcT7lO7GsGZq2G4IlT" >>"$CONF"

  echo "Now you can login to your Google Account in Chromium."
fi
