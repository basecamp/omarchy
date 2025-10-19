echo "Add UWSM env"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH"

mkdir -p "$HOME/.config/uwsm/"
cat <<EOF | tee "$HOME/.config/uwsm/env"
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin/:$PATH
EOF

mkdir -p ~/.local/state/omarchy/migrations
touch ~/.local/state/omarchy/migrations/1751134560.sh

sudo systemctl restart systemd-timesyncd
bash omarchy-update-perform
