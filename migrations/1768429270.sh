echo "Fix volume controls for laptops with problematic Realtek codecs (like Asus G14)"

mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp $OMARCHY_PATH/config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf ~/.config/wireplumber/wireplumber.conf.d/
rm ~/.local/state/wireplumber/default-routes
systemctl --user restart wireplumber
