if true; then
  cat <<-EOF | sudo tee /etc/omarchy/indented.conf >/dev/null
	helper=$HOME/.local/share/omarchy/bin/omarchy-agent
	EOF
fi
