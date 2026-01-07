echo "Remove direct symlink to Mako config in theme, and copy over the new Mako config."

# If there's a symlink, remove it and copy over the new config file.
if [[ -L ~/.config/mako/config ]]; then
  rm -f ~/.config/mako/config
  cp $OMARCHY_PATH/config/mako/config ~/.config/mako/config
fi
