# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

**This is a custom branch maintained by [constantinchik](https://github.com/constantinchik).**

Read more at [omarchy.org](https://omarchy.org).

## Installation

### Fresh Installation

To install Omarchy from scratch, boot into an Arch Linux live environment and run:

```bash
bash <(curl -s https://raw.githubusercontent.com/constantinchik/omarchy/master/boot.sh)
```

This will:
- Clone the repository to `~/.local/share/omarchy/`
- Run the installation process (`install.sh`)
- Install all base packages, configure the system, and set up Hyprland
- Mark all migrations as complete
- Set up boot splash, display manager, and bootloader

### Using a Custom Branch

To install from a specific branch:

```bash
OMARCHY_REF=your-branch-name bash <(curl -s https://raw.githubusercontent.com/constantinchik/omarchy/master/boot.sh)
```

## Development Setup

If you want to develop and test changes to your Omarchy configuration:

### 1. Clone the Repository

```bash
git clone git@github.com:constantinchik/omarchy.git ~/Projects/omarchy
cd ~/Projects/omarchy
```

### 2. Link Development Repository

Replace the installed Omarchy directory with a symlink to your development repo:

```bash
# Backup the current installation
mv ~/.local/share/omarchy ~/.local/share/omarchy.backup

# Create symlink to your development repo
ln -s ~/Projects/omarchy ~/.local/share/omarchy
```

### 3. Deploy Configuration Changes

After making changes to config files in your dev repo:

```bash
# Deploy specific config file (creates backup and shows diff)
omarchy-refresh-config hypr/monitors.conf

# Or reload Hyprland to test changes
hyprctl reload
```

### Development Workflow

**Making Changes:**
- Edit files in `~/Projects/omarchy`
- Use `omarchy-refresh-config <path>` to deploy configs to `~/.config/`
- Reload Hyprland or restart themed components to see changes

**Creating Migrations:**
When making changes that need to be applied to existing installations:

```bash
omarchy-dev-add-migration
```

This creates a timestamped migration file in `migrations/`. Edit it to include your update commands.

**Testing Migrations:**

```bash
omarchy-migrate  # Run pending migrations
```

**Package Management:**
- Add core packages to `install/omarchy-base.packages`
- Add optional packages to `install/omarchy-other.packages`
- Install packages with `omarchy-pkg-add package-name`

### Useful Commands

- `omarchy-update-perform` - Full system update with migrations
- `omarchy-theme-set <name>` - Switch themes
- `omarchy-migrate` - Run pending migrations
- `omarchy-refresh-config <path>` - Deploy updated config files

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
