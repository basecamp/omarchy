echo "Make Alacritty compatible with X-TerminalArgs"

if omarchy-pkg-present alacritty; then
  mkdir -p ~/.local/share/applications
  cat > ~/.local/share/applications/Alacritty.desktop << EOF
[Desktop Entry]
Type=Application
TryExec=alacritty
Exec=alacritty
Icon=Alacritty
Terminal=false
Categories=System;TerminalEmulator;
Name=Alacritty
GenericName=Terminal
Comment=A fast, cross-platform, OpenGL terminal emulator
StartupNotify=true
StartupWMClass=Alacritty
Actions=New;
X-TerminalArgExec=-e
X-TerminalArgAppId=--class=
X-TerminalArgTitle=--title=
X-TerminalArgDir=--working-directory=

[Desktop Action New]
Name=New Terminal
Exec=alacritty
EOF
fi
