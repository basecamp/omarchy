echo "Adding auto suspend after 7 min"

# Add the auto suspend listener to hypridle.conf
if ! grep -q 'on-timeout *= *systemctl suspend' ~/.config/hypr/hypridle.conf; then
    cp ~/.config/hypr/hypridle.conf ~/.config/hypr/hypridle.bak.$(date +%s)
    sed -i '$a\
\
listener {\
    timeout = 420                  # 7min\
    on-timeout = systemctl suspend\
}' ~/.config/hypr/hypridle.conf
else
    echo "Auto suspend listener already present in hypridle.conf, skipping."
fi
