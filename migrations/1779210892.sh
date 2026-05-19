echo "Remove Walker app-launcher services and Elephant providers"

pkill elephant 2>/dev/null || true
systemctl --user disable --now elephant.service 2>/dev/null || true
systemctl --user disable --now app-walker@autostart.service 2>/dev/null || true
rm -f ~/.config/autostart/walker.desktop
rm -rf ~/.config/elephant
rm -rf ~/.config/systemd/user/app-walker@autostart.service.d
sudo rm -f /etc/pacman.d/hooks/walker-restart.hook

for bindings_file in ~/.config/hypr/bindings/utilities.lua ~/.config/hypr/bindings.lua; do
  if [[ -f $bindings_file ]]; then
    sed -i 's#omarchy-launch-walker#omarchy-shell shell toggle omarchy.app-launcher \\"{}\\"#g' "$bindings_file"
  fi
done

omarchy-pkg-drop \
  omarchy-walker \
  elephant-all \
  elephant \
  elephant-calc \
  elephant-clipboard \
  elephant-bluetooth \
  elephant-desktopapplications \
  elephant-files \
  elephant-menus \
  elephant-providerlist \
  elephant-runner \
  elephant-symbols \
  elephant-unicode \
  elephant-websearch \
  elephant-todo
