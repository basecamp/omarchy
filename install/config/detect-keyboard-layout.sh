# Copy over the keyboard layout that's been set in Arch during install to Hyprland
conf="/etc/vconsole.conf"
hyprconf="$HOME/.config/hypr/input.conf"

layout=""
variant=""

if grep -q '^XKBLAYOUT=' "$conf"; then
  layout=$(grep '^XKBLAYOUT=' "$conf" | cut -d= -f2 | tr -d '"')
fi

if grep -q '^XKBVARIANT=' "$conf"; then
  variant=$(grep '^XKBVARIANT=' "$conf" | cut -d= -f2 | tr -d '"')
fi

# Fallback: derive XKB layout/variant from KEYMAP when XKBLAYOUT is absent
if [[ -z "$layout" ]] && grep -q '^KEYMAP=' "$conf"; then
  keymap=$(grep '^KEYMAP=' "$conf" | cut -d= -f2 | tr -d '"')
  case "$keymap" in
    dvorak*)    layout="us"; variant="dvorak" ;;
    colemak*)   layout="us"; variant="colemak" ;;
    fr-bepo)    layout="fr"; variant="bepo" ;;
    uk|uk-*)    layout="gb" ;;
    us|us-*)    layout="us" ;;
    de|de-*)    layout="de" ;;
    fr|fr-*)    layout="fr" ;;
    es|es-*)    layout="es" ;;
    it|it-*)    layout="it" ;;
    pt|pt-*)    layout="pt" ;;
    br|br-*)    layout="br" ;;
    ru|ru-*)    layout="ru" ;;
    pl|pl-*)    layout="pl" ;;
    se|se-*)    layout="se" ;;
    no|no-*)    layout="no" ;;
    dk|dk-*)    layout="dk" ;;
    fi|fi-*)    layout="fi" ;;
    ch|ch-*)    layout="ch" ;;
    nl|nl-*)    layout="nl" ;;
    cz|cz-*)   layout="cz" ;;
    hu|hu-*)    layout="hu" ;;
    ro|ro-*)    layout="ro" ;;
    jp|jp-*)    layout="jp" ;;
    kr|kr-*)    layout="kr" ;;
    *)          layout="${keymap:0:2}" ;;
  esac
fi

if [[ -n "$layout" ]]; then
  sed -i "/^[[:space:]]*kb_options *=/i\  kb_layout = $layout" "$hyprconf"
fi

if [[ -n "$variant" ]]; then
  sed -i "/^[[:space:]]*kb_options *=/i\  kb_variant = $variant" "$hyprconf"
fi
