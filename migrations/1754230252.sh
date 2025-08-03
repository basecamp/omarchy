echo "Install Tmux and tpm (Tmux Package Manager)"

if ! yay -Qe tmux &>/dev/null; then
  yay -S --noconfirm --needed tmux
fi


if [[ ! -d ~/.tmux/plugins/tpm ]]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
