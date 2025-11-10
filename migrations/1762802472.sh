echo "Append custom Ctrl+X and Ctrl+R bindings for imv; backup existing config if present"

if [ -f ~/.config/imv/config ]; then
  cp ~/.config/imv/config ~/.config/imv/config.bak.$(date +%s)
else
  mkdir -p ~/.config/imv
fi

cat >>~/.config/imv/config <<'EOF'

# Delete and then close an open image by pressing 'Ctrl+x'
<Ctrl+x> = exec rm "$imv_current_file"; close

# Rotate the currently open image by 90 degrees by pressing 'Ctrl+r'
<Ctrl+r> = exec mogrify -rotate 90 "$imv_current_file"
EOF
