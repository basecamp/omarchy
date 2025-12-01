echo "Add a default keyring for gnome-keyring that unlocks on login"

if [ -f "$HOME/.local/share/keyrings/Default_keyring.keyring" ] || [ -f "$HOME/.local/share/keyrings/default" ]; then
    if gum confirm "Do you want to replace existing keyring with one that's auto-unlocked on login?"; then
        bash "$OMARCHY_PATH/install/login/default-keyring.sh"
    fi
else
    bash "$OMARCHY_PATH/install/login/default-keyring.sh"
fi
