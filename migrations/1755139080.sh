echo "Ensure fcitx5 does not overwrite xkb layout"

FCITX5_CONF_DIR="$HOME/.config/fcitx5/conf"
FCITX5_XCB_CONF="$FCITX5_CONF_DIR/xcb.conf"

if [[ ! -f $FCITX5_XCB_CONF ]]; then
  mkdir -p "$FCITX5_CONF_DIR"
  cp "$OMARCHY_PATH/config/fcitx5/conf/xcb.conf" "$FCITX5_XCB_CONF"
fi
