echo "Align default apps and services with custom Omarchy package set"

omarchy-pkg-drop \
  1password-beta \
  1password-cli \
  signal-desktop \
  typora \
  claude-code \
  dotnet-runtime-9.0

omarchy-pkg-add \
  audacity \
  bitwarden \
  bitwarden-cli \
  go \
  python \
  tailscale \
  visual-studio-code-bin \
  wireshark-qt

omarchy-webapp-remove \
  HEY \
  Basecamp \
  WhatsApp \
  Fizzy

rm -f ~/.local/share/applications/typora.desktop

sudo systemctl enable tailscaled.service

if getent group wireshark >/dev/null; then
  sudo usermod -aG wireshark ${USER}
fi

mkdir -p ~/.vscode ~/.config/Code/User

if [[ ! -f ~/.vscode/argv.json ]]; then
  cat >~/.vscode/argv.json <<'EOF'
// This configuration file allows you to pass permanent command line arguments to VS Code.
// Only a subset of arguments is currently supported to reduce the likelihood of breaking
// the installation.
//
// PLEASE DO NOT CHANGE WITHOUT UNDERSTANDING THE IMPACT
//
// NOTE: Changing this file requires a restart of VS Code.
{
  "password-store": "gnome-libsecret"
}
EOF
fi

if [[ ! -f ~/.config/Code/User/settings.json ]]; then
  printf '{\n  "update.mode": "none"\n}\n' >~/.config/Code/User/settings.json
fi
