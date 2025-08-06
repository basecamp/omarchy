# Dynamic Bash Prompt

This enhancement replaces the simple default bash prompt with a dynamic, theme-aware prompt that automatically adapts to any Omarchy theme.

## Features

- **Dynamic color extraction** - Automatically reads colors from `alacritty.toml` 
- **Light/dark theme support** - Detects `light.mode` files and adjusts text brightness
- **Git integration** - Shows current branch and status
- **Universal compatibility** - Works with all themes without requiring additional files
- **Performance optimized** - Caches colors and only updates when theme changes

## How It Works

The prompt extracts colors from the current theme's `alacritty.toml` file using pattern matching:
- Foreground color for main text
- Standard terminal colors (blue, purple, cyan, green, yellow) for UI elements
- Automatic text dimming in light themes for better readability

## Theme Compatibility

Works automatically with any theme containing:
- `alacritty.toml` with standard color definitions
- Optional `light.mode` file for light theme detection

No additional files needed in theme directories.

## Usage

The prompt is automatically loaded when sourcing `default/bash/prompt`. Users can add to their `.bashrc`:

```bash
# Load Omarchy dynamic prompt
source ~/.config/omarchy/default/bash/prompt
```

## Prompt Format

```
╭─[ user@hostname ]─[ /current/path ] main✓
╰─❯❯❯ 
```

- Blue borders and arrows
- Purple username section  
- Yellow path section
- Purple git branch with green/red status indicator
- Cyan final prompt character