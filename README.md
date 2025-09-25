# Omarchy

```
                 ▄▄▄                                                   
 ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄ 
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   █▀   ███   ███  ███   ███
███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███
███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███
███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███
███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   █▀    ▀█████▀ 
                                       ███   █▀                                  
```

**Beautiful, Modern & Opinionated Linux by [DHH](https://dhh.dk/)**

Turn a fresh Arch installation into a fully-configured, beautiful, and modern web development system based on Hyprland by running a single command. That's the one-line pitch for Omarchy. No need to write bespoke configs for every essential tool just to get started or to be up on all the latest command-line tools. Omarchy is an opinionated take on what Linux can be at its best.

## 🚀 Quick Start

### Option 1: One-Line Installation (Recommended)
Transform your fresh Arch Linux installation with a single command:

```bash
bash <(curl -s https://raw.githubusercontent.com/basecamp/omarchy/master/boot.sh)
```

### Option 2: Download the ISO
Get the pre-built Omarchy ISO for a complete installation experience:

**[📥 Download Omarchy 3.0.1 ISO](https://iso.omarchy.org/omarchy-3.0.1.iso)**

### Requirements
- Fresh Arch Linux installation (minimal base system)
- Internet connection
- At least 4GB RAM recommended
- 20GB+ available disk space

## 🎯 Philosophy

Omarchy embodies the principle that **great defaults lead to great productivity**. Instead of spending weeks configuring your Linux environment, Omarchy gives you:

- **Opinionated Excellence**: Carefully curated tools and configurations that work beautifully together
- **Modern Aesthetics**: A stunning Hyprland-based desktop that's both functional and beautiful  
- **Developer-First**: Everything a modern web developer needs, pre-configured and ready to go
- **Minimal Maintenance**: Sane defaults that just work, letting you focus on what matters

This isn't just another Linux distribution—it's a philosophy of computing that values your time and creativity.

## ✨ What's Included

Omarchy comes with **130+ carefully selected packages** including:

### 🖥️ Desktop Environment
- **Hyprland** - Modern Wayland compositor with beautiful animations
- **Waybar** - Highly customizable status bar
- **Walker** - Application launcher and file manager
- **Mako** - Notification daemon

### 🛠️ Development Tools
- **Neovim** with LazyVim configuration
- **Docker** & Docker Compose
- **Git** with GitHub CLI
- **Mise** - Runtime version manager
- **Lazygit** & Lazydocker - TUI interfaces

### 📱 Applications
- **Brave Browser** (Chromium-based)
- **Obsidian** - Knowledge management
- **Typora** - Markdown editor  
- **Signal Desktop** - Secure messaging
- **Spotify** - Music streaming
- **LibreOffice** - Office suite
- **OBS Studio** - Screen recording/streaming

### 🎨 Theming & Fonts
- **Nerd Fonts** (Cascadia Code, JetBrains Mono)
- **Noto Fonts** with emoji support
- **Kvantum** theming engine
- Custom Omarchy branding

### 🔧 System Tools
- **Fastfetch** - System information
- **Btop** - System monitor
- **Starship** - Cross-shell prompt
- **Zoxide** - Smarter cd command
- **Ripgrep**, **fd**, **bat**, **eza** - Modern CLI tools

## 📚 Documentation & Resources

- **🌐 Official Website**: [omarchy.org](https://omarchy.org)
- **📖 Complete Manual**: [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual)
- **💬 Discord Community**: [Join our Discord](https://discord.gg/tXFUdasqhY)
- **🛒 Official Merch**: [37signals Supply](https://supply.37signals.com/collections/omarchy)
- **💻 Workstation Gallery**: [omarchy.org/workstations](https://omarchy.org/workstations/)

## 🤝 Community & Support

- **GitHub Issues**: Report bugs and request features
- **Discord**: Get help from the community and maintainers
- **Discussions**: Share your setup and ask questions

## 🏗️ Development

### Project Structure
```
omarchy/
├── install/           # Installation scripts and package lists
├── config/           # Application configurations
├── themes/           # Visual themes and styling
├── applications/     # Desktop application entries
├── bin/             # Utility scripts
└── boot.sh          # Main installation entry point
```

### Contributing
We welcome contributions! Please see our contributing guidelines and join our Discord for coordination.

### Custom Installation
You can customize your Omarchy installation by setting environment variables:

```bash
# Use a custom repository
export OMARCHY_REPO="yourusername/omarchy"

# Use a specific branch
export OMARCHY_REF="your-branch"

bash <(curl -s https://raw.githubusercontent.com/basecamp/omarchy/master/boot.sh)
```

## 📄 License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).

---

**Brought to you by [37signals](https://37signals.com)** 🏔️

