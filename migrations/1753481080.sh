if [[ $(lspci -d ::03xx | grep -i "intel") ]]; then
  yay -S --needed --noconfirm intel-media-driver
fi
