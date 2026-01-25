# Omarchy on NixOS

This project creates a reproducible implementation of the Omarchy experience
specifically for NixOS users. It packages the custom scripts, themes, and
configurations that define Omarchy primarily as a Home Manager module.

To head off the inevitable "why didn't you use the project linked from the
official website?!" questions: I took a look at it when it was in its infancy
and could tell it wasn't what I wanted to do. I've been writing software for a
long time, and I knew a reimplementation would not be sustainable. This bore
out, as that original project has been abandoned.

## Goals

* **Faithful Reproduction:** Bring the "beautiful, modern & opinionated"
    design of Omarchy to the declarative world of NixOS.
* **Upstream Alignment:** Stay up to date with the original Omarchy project
    by developing as a set of patches on top of upstream rather than a
    bespoke reimplementation.
* **Seamless Integration:** Provide an easy-to-use Home Manager module that
    can be dropped into existing configurations.
* **Tooling Consistency:** Port the extensive suite of `omarchy-*` CLI tools
    and scripts to work natively within the Nix store environment where they
    make sense, using native NixOS functions when better or more appropriate.

## Non-Goals

* **Total Feature Parity:** It is not a goal to bring every single feature
    from Omarchy over, especially where they conflict with NixOS idioms or
    provide redundant functionality already handled by the ecosystem.
* **Standalone Distribution:** This project is not intended to be a
    replacement for the NixOS installer or a "distro-on-top-of-distro"; it is
    a configuration module for existing NixOS systems.
* **Support for Non-Flake Configurations:** We rely on Flakes for dependency
    management and reproducibility.

## Getting Started

### Prerequisites

* A running NixOS installation.
* Flakes enabled in your Nix configuration.

### Installation

1. **Add the Input:** Add `omarchy` to your `flake.nix` inputs:

    ```nix
    inputs = {
      # ...
      omarchy = {
        url = "github:codingismy11to7/omarchy";
        inputs.nixpkgs.follows = "nixpkgs";
        inputs.home-manager.follows = "home-manager";
      };
    };
    ```

2. **Configure Binary Cache (Recommended):** To avoid compiling from source,
    add the binary cache to your `flake.nix` or `nix.conf`.

    ```nix
    nixConfig = {
      extra-substituters = [ "https://nix-cache.codingismy11to7.us/omarchy" ];
      extra-trusted-public-keys = [
        "omarchy:TRPnFp7RNU+BhR64bXpG61cNE7TlB53BAoc7wEmhzyE="
      ];
    };
    ```

3. **Import the Module:** Add the module to your system configuration.

    **Home Manager:**

    ```nix
    # In your home-manager configuration file
    imports = [
      inputs.omarchy.homeManagerModules.default
    ];

    omarchy = {
      enable = true;
      # Need hyprland from unstable or git, if you're using stable nixpkgs
      hyprland.package = pkgs.unstable.hyprland;
      # need a chromium-based browser for the omarchy-launch-webapp tool
      browser = "brave";
    };
    ```

    **NixOS System-wide:**

    While Omarchy is designed for Home Manager, a system module is available
    for system-level integrations.

    ```nix
    # In your configuration.nix
    imports = [
      inputs.omarchy.nixosModules.default
    ];

    omarchy = {
      enable = true;
      hyprland.package = pkgs.unstable.hyprland;
    };
    ```

    **LazyVim Theme:**

    You can also import the current Omarchy theme into your LazyVim configuration.
    Here is an example using `mkNeovim` from the
    [nixPatch-nvim](https://codeberg.org/NicoElbers/nixPatch-nvim) flake:

    ```nix
    home.packages = [
      (inputs.nvim.lib.mkNeovim {
        pkgs = pkgs.unstable;
        inherit (pkgs.stdenv.hostPlatform) system;
        theme = {
          content = inputs.omarchy.lazyvimTheme.default { inherit config; };
        };
      })
    ];
    ```

## Differences from Omarchy

While we strive for faithful reproduction, some adjustments have been made for
NixOS compatibility and improved ergonomics for Vim users:

* **Vim-style Keybindings:** Several Hyprland keybindings have been remapped
    to avoid conflicts with standard `hjkl` navigation (e.g., lock screen and
    keyboard shortcut viewer).
* **Logout Shortcut:** Added a dedicated shortcut to log out to the display
    manager.
* **NixOS Adaptations:** Various underlying paths and configurations have
    been adjusted to respect the read-only nature of the Nix store and the
    declarative system model.

## Plans

* **Expanded Customization:** Obviate the need for hardcoded customizations
    by exposing more configuration options. PRs are welcome!
* **Stylix Integration:** Configure [Stylix](https://github.com/danth/stylix)
    or export a Stylix-compatible theme that matches the current Omarchy aesthetic.
* **Quick Start / Installer:** Longer term, potentially port the installer logic
    or create a "quick start" flake template to bootstrap a full Omarchy system
    from scratch.

### Development

To hack on Omarchy for NixOS locally:

```bash
nix develop # if you don't use direnv
dev-mode # Starts a file watcher to check your build
```

---

# Original README

# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
