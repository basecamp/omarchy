echo "Migrate starship configuration to preset system"

# Create presets directory
mkdir -p ~/.config/starship/presets

# Migrate existing starship.toml to default preset
if [ -f ~/.config/starship.toml ]; then
    mv ~/.config/starship.toml ~/.config/starship/presets/starship.toml
    echo "Migrated existing starship.toml to starship preset"
fi

# Copy new presets from omarchy
cp $OMARCHY_PATH/config/starship/presets/*.toml ~/.config/starship/presets/ 2>/dev/null || true

# Set default preset if none exists
if [ ! -f ~/.config/starship/presets/current_preset ]; then
    echo "starship" > ~/.config/starship/presets/current_preset
fi
