#!/bin/bash
echo "Installing darkman for automatic theme switching"

# Install darkman if not present
if ! command -v darkman &>/dev/null; then
  yay -S --noconfirm --needed darkman
fi

# Create XDG data directories for darkman hooks
DARK_MODE_DIR="$HOME/.local/share/dark-mode.d"
LIGHT_MODE_DIR="$HOME/.local/share/light-mode.d"

mkdir -p "$DARK_MODE_DIR"
mkdir -p "$LIGHT_MODE_DIR"

# Install hook scripts in XDG data directories
cat >"$DARK_MODE_DIR/omarchy-theme-dark" <<'EOF'
#!/bin/bash
# Darkman hook for dark mode
# Applies the dark theme using Omarchy scripts

# Source Omarchy config to get theme names
CONFIG_FILE="$HOME/.config/omarchy/theme-auto-switch.conf"
if [ -f "$CONFIG_FILE" ]; then
  # Simple key=value parsing
  DARK_THEME=$(grep "^dark_theme = " "$CONFIG_FILE" | cut -d'"' -f2)
  ENABLE_HYPRSUNSET=$(grep "^hyprsunset_enabled = " "$CONFIG_FILE" | cut -d' ' -f3)

  # Set defaults if parsing failed
  DARK_THEME=${DARK_THEME:-"tokyo-night"}
  ENABLE_HYPRSUNSET=${ENABLE_HYPRSUNSET:-"false"}
else
  DARK_THEME="tokyo-night"
  ENABLE_HYPRSUNSET="false"
fi

# Apply dark theme
omarchy-theme-set "$DARK_THEME"

# Optional: Set night temperature for hyprsunset
if [ "$ENABLE_HYPRSUNSET" = "true" ]; then
  hyprctl hyprsunset temperature 4000  # Set to nightlight temperature
fi

echo "Switched to dark theme: $DARK_THEME"
EOF
chmod +x "$DARK_MODE_DIR/omarchy-theme-dark"
echo "Installed dark mode hook to $DARK_MODE_DIR/omarchy-theme-dark"

cat >"$LIGHT_MODE_DIR/omarchy-theme-light" <<'EOF'
#!/bin/bash
# Darkman hook for light mode
# Applies the light theme using Omarchy scripts

# Source Omarchy config to get theme names
CONFIG_FILE="$HOME/.config/omarchy/theme-auto-switch.conf"
if [ -f "$CONFIG_FILE" ]; then
  # Simple key=value parsing
  LIGHT_THEME=$(grep "^light_theme = " "$CONFIG_FILE" | cut -d'"' -f2)
  ENABLE_HYPRSUNSET=$(grep "^hyprsunset_enabled = " "$CONFIG_FILE" | cut -d' ' -f3)

  # Set defaults if parsing failed
  LIGHT_THEME=${LIGHT_THEME:-"catppuccin-latte"}
  ENABLE_HYPRSUNSET=${ENABLE_HYPRSUNSET:-"false"}
else
  LIGHT_THEME="catppuccin-latte"
  ENABLE_HYPRSUNSET="false"
fi

# Apply light theme
omarchy-theme-set "$LIGHT_THEME"

# Optional: Set day temperature for hyprsunset
if [ "$ENABLE_HYPRSUNSET" = "true" ]; then
  hyprctl hyprsunset temperature 6000  # Set to daylight temperature
fi

echo "Switched to light theme: $LIGHT_THEME"
EOF
chmod +x "$LIGHT_MODE_DIR/omarchy-theme-light"
echo "Installed light mode hook to $LIGHT_MODE_DIR/omarchy-theme-light"

# Copy theme-auto-switch.conf if it doesn't exist
if [ ! -f ~/.config/omarchy/theme-auto-switch.conf ]; then
  cp config/theme-auto-switch.conf ~/.config/omarchy/
  echo "Copied theme-auto-switch.conf to ~/.config/omarchy/"
else
  echo "Theme auto-switch config already exists at ~/.config/omarchy/theme-auto-switch.conf"
fi

echo ""
echo "To activate pick Toggle > Theme Auto Switch from the Omarchy menu."
echo "Darkman setup complete"
