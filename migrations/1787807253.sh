echo "Remove the unconstrained asdcontrol sudoers file"

[[ -e /etc/sudoers.d/asdcontrol || -L /etc/sudoers.d/asdcontrol ]] || exit 0
sudo rm -f /etc/sudoers.d/asdcontrol
