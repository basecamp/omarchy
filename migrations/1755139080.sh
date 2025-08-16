echo "Ensure fcitx5 does not overwrite xkb layout."

FCITX5_CONF_DIR="${HOME}/.config/fcitx5/conf"
FCITX5_XCB_CONF="${FCITX5_CONF_DIR}/xcb.conf"

mkdir -p "${FCITX5_CONF_DIR}"

if [ ! -f "${FCITX5_XCB_CONF}" ]; then
    touch "${FCITX5_XCB_CONF}"
    echo "# Default config to prevent fcitx5 from overwriting XKB layout" >> "${FCITX5_XCB_CONF}"
    echo 'Allow Overriding System XKB Settings=False' >> "${FCITX5_XCB_CONF}"
fi
