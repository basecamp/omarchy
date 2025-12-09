echo "Remove direct symlink to Mako config in theme, and copy over the new Mako config."

# If there's a symlink, remove it and copy over the new config file.
if test -L ~/.config/mako/config; then
  rm -f ~/.config/mako/config && cp ~/.local/share/omarchy/config/mako/config ~/.config/mako/config
# Else, a real config file already exists. Note as such and don't do anything.
elif test -f ~/.config/mako/config; then
  echo "Mako config file already exists, skipping."
fi
