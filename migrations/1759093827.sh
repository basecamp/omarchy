echo "Adding hidden entries for electron apps"

tee ~/.local/share/applications/electron36.desktop >/dev/null <<EOF
[Desktop Entry]
Hidden=true
EOF

tee ~/.local/share/applications/electron37.desktop >/dev/null <<EOF
[Desktop Entry]
Hidden=true
EOF