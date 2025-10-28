echo "Disable Nvim news alerts box"

cat <<EOF

This will add a config file to disable it:
  ~/.config/nvim/lua/plugins/disable-news-alert.lua

EOF

cp /usr/share/omarchy-nvim/config/lua/plugins/disable-news-alert.lua ~/.config/nvim/lua/plugins/disable-news-alert.lua
