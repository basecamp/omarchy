echo "Pin browser password store to gnome-libsecret (prevents cookie/login loss on Hyprland)"

# Chromium and Brave auto-detect their os_crypt backend; on Hyprland the xdg-desktop-portal Secret
# backend has no provider and fails, so they can fall back to the 'basic' (v10) store. A swap from
# the gnome-libsecret (v11) key to the basic key makes existing cookies and saved passwords
# undecryptable, so the browser silently drops them and the user is logged out of everything.
# Pin gnome-libsecret so the backend is deterministic across reboots and updates.
for conf in ~/.config/chromium-flags.conf ~/.config/brave-flags.conf; do
    if [[ -f $conf ]] && ! grep -q -- '--password-store=' "$conf"; then
        echo '--password-store=gnome-libsecret' >> "$conf"
    fi
done
