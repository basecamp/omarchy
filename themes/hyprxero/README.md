# HyprXero Theme for oh-my-arch

This directory contains a port of the popular HyprXero theme, adapted for the `oh-my-arch` framework. It includes configuration files for Hyprland, Waybar, Kitty, Rofi, and other components to replicate the aesthetic of the HyprXero desktop.

All credit for the original theme design and configuration goes to the **XeroLinux team**. This package simply ports the theme into the `oh-my-arch` structure.

## Installation

**IMPORTANT:** This theme pack only contains the configuration files. It **does not** install the necessary applications, fonts, or icons required for the theme to work correctly.

### 1. Install Dependencies

Before applying the theme, you must manually install the required packages. You can find a list of these packages in the `install.sh` script of the original [HyprXero repository](https://github.com/xerolinux/HyprXero-git).

### 2. Apply the Theme

Once you have installed the dependencies, you can apply the theme by running the included shell script.

```bash
cd themes/hyprxero
./apply_theme.sh
```

This script will back up your existing configurations for `hypr`, `kitty`, `rofi`, etc., to a timestamped directory in your home folder before copying the new theme files into place.

## Notes and Missing Files

During the porting process, I was unable to retrieve a few files. You may need to find or create these manually for the complete theme experience:

*   **`rofi/config.rasi`**: The main Rofi configuration file could not be downloaded due to a persistent tool error. The `rofi` theme will be incomplete without this file.
*   **`wlogout` Icons**: The icons for the logout menu (e.g., `lock.png`, `shutdown.png`) are not included. The `wlogout` package itself should provide default icons, but for the full theme, you may need to source them from the original HyprXero repository.
*   **`waybar/modules/software.sh`**: This script was referenced but could not be found in the repository. It is likely non-essential.

Enjoy your new look!
