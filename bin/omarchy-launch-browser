#!/bin/bash

# Launch the default browser as determined by xdg-settings.
# Automatically converts --private into the correct flag for the given browser.

default_browser=$(xdg-settings get default-web-browser)
browser_exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/$default_browser 2>/dev/null | head -1)

if [[ $browser_exec =~ (firefox|zen|librewolf|mullvad) ]]; then
  private_flag="--private-window"
elif [[ $browser_exec =~ edge ]]; then
  private_flag="--inprivate"
else
  private_flag="--incognito"
fi

exec setsid uwsm-app -- "$browser_exec" "${@/--private/$private_flag}"
