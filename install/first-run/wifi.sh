if ! ping -c3 -W1 1.1.1.1 >/dev/null 2>&1; then

  INTERFACE=$(iwctl station list | tail -n +5 | awk '{print $2}' | tr -d " \t\n\r")
  if [[ -z "$INTERFACE" ]]; then
      notify-send "Error" "No wireless interface found" -u critical
      exit 1
  fi

  iwctl station $INTERFACE scan
  if iwctl station $INTERFACE get-networks | grep -qF "eduroam"; then
      if ! yay -S --noconfirm geteduroam; then
          notify-send "Error" "Failed to install geteduroam package" -u critical
          exit 1
      fi
      RESPONSE=$(notify-send --action 'default=Open URL' 'Eduroam Network Detected' 'The eduroam network has been detected. Click here to begin connecting or right click to dismiss.' -u normal -i dialog-information -t 10000)
      if [[ $RESPONSE == *"default"* ]]; then
          geteduroam-gui &
          exit
      fi
      yay -R --noconfirm geteduroam
  fi

  notify-send "󰖩    Click to Setup Wi-Fi" "Tab to navigate, Space to select, ? for help." -u critical -t 30000
fi
