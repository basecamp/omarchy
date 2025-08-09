# Omarchy

Turn a fresh Arch installation into a fully-configured, beautiful, and modern web development system based on Hyprland by running a single command. That's the one-line pitch for Omarchy (like it was for Omakub). No need to write bespoke configs for every essential tool just to get started or to be up on all the latest command-line tools. Omarchy is an opinionated take on what Linux can be at its best.

Read more at [omarchy.org](https://omarchy.org).

## Prerequisites

Before installing Omarchy, ensure you have the following tools installed on your Arch Linux system:

- **wget** or **curl** - HTTP client (required for downloading the installer)

On a fresh Arch Linux installation, you can install these prerequisites with:

```bash
# Install wget
sudo pacman -S wget

# Or use curl instead of wget
sudo pacman -S curl
```

## Installation

Run one of the following commands to install Omarchy:

### Using wget:
```bash
wget -qO- https://omarchy.org/boot.sh | bash
```

### Using curl:
```bash
curl -fsSL https://omarchy.org/boot.sh | bash
```

The installer will:
1. Check that you're not running as root (and offer to create a user if needed)
2. Check for all required prerequisites (and install them if missing)
3. Clone the Omarchy repository
4. Run the complete installation process
5. Reboot your system when finished

**Important Notes:**
- **Do not run as root**: The installer should be run as a normal user with sudo permissions. If you're running as root, the installer will offer to create a new user account for you.
- **Internet connection required**: The installation process downloads packages and repositories.
- **System changes**: The installer makes system-wide changes. Make sure you have backups of any important data before proceeding.

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).

