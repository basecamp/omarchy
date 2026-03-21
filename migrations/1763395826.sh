echo "Add GTK-4.0 theme support with base styles"

# Create GTK-4.0 config directory
mkdir -p ~/.config/gtk-4.0

# Symlink base style
ln -snf ~/.local/share/omarchy/default/gtk/style.css ~/.config/gtk-4.0/style.css

# Symlink current theme's GTK CSS
ln -snf ~/.config/omarchy/current/theme/gtk.css ~/.config/gtk-4.0/gtk.css
