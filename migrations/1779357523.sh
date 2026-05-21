echo "Move launcher hides from hidden desktop overrides to launcher.hides"

remove_legacy_hidden_override() {
  local file=$1
  local line
  local found_section=false
  local found_hidden=false

  [[ -f $file ]] || return

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z $line ]] && continue

    case $line in
      "[Desktop Entry]")
        found_section=true
        ;;
      "Hidden=true")
        found_hidden=true
        ;;
      *)
        return
        ;;
    esac
  done < "$file"

  if [[ $found_section == "true" && $found_hidden == "true" ]]; then
    rm -f "$file"
  fi
}

for app in \
  avahi-discover \
  bssh \
  btop \
  bvnc \
  cmake-gui \
  cups \
  dropbox \
  electron34 \
  electron36 \
  electron37 \
  fcitx5-configtool \
  fcitx5-wayland-launcher \
  foot-server \
  footclient \
  java-java-openjdk \
  jconsole-java-openjdk \
  jshell-java-openjdk \
  kbd-layout-viewer5 \
  kcm_fcitx5 \
  kcm_kaccounts \
  kvantummanager \
  libreoffice-base \
  libreoffice-draw \
  libreoffice-math \
  libreoffice-startcenter \
  libreoffice-xsltfilter \
  limine-snapper-restore \
  lstopo \
  org.fcitx.Fcitx5 \
  org.fcitx.fcitx5-config-qt \
  org.fcitx.fcitx5-migrator \
  org.fcitx.fcitx5-qt5-gui-wrapper \
  org.fcitx.fcitx5-qt6-gui-wrapper \
  qv4l2 \
  qvidcap \
  uuctl \
  xgps \
  xgpsspeed; do
  remove_legacy_hidden_override "$HOME/.local/share/applications/$app.desktop"
done

update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true
