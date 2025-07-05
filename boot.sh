ascii_art='       d8888                 888                        888    888    
      d88888                 888                        888    888    
     d88P888                 888                        888    888    
    d88P 888 888d888 .d8888b 88888b.  888  888 888  888 888888 888888 
   d88P  888 888P"  d88P"    888 "88b 888  888 888  888 888    888    
  d88P   888 888    888      888  888 888  888 888  888 888    888    
 d8888888888 888    Y88b.    888  888 Y88b 888 Y88b 888 Y88b.  Y88b.  
d88P     888 888     "Y8888P 888  888  "Y88888  "Y88888  "Y888  "Y888 
                                           888      888               
                                      Y8b d88P Y8b d88P               
                                       "Y88P"   "Y88P"                '

echo -e "\n$ascii_art\n"

echo -e "\nYou are on Archyytt, a fork of Omarchy!\n"

pacman -Q git &>/dev/null || sudo pacman -Sy --noconfirm --needed git

echo -e "\nCloning Omarchy..."
rm -rf ~/.local/share/omarchy/
git clone https://github.com/ThiaudioTT/archyytt.git ~/.local/share/omarchy >/dev/null

# Use custom branch if instructed
if [[ -n "$OMARCHY_REF" ]]; then
  echo -e "\eUsing branch: $OMARCHY_REF"
  cd ~/.local/share/omarchy
  git fetch origin "${OMARCHY_REF}" && git checkout "${OMARCHY_REF}"
  cd -
fi

echo -e "\nInstallation starting..."
source ~/.local/share/omarchy/install.sh
