# Fedora Conversion Summary

This document summarizes the changes made to convert the Omarchy installation from Arch Linux to Fedora Linux.

## Major Changes Made

### Package Manager Conversion

- **Changed**: All `pacman` and `yay` commands converted to `dnf`
- **Changed**: Package names adapted to Fedora equivalents where available

### System-Specific Changes

#### Boot Script (`boot.sh`)

- Changed `pacman -Q git` to `rpm -q git`
- Changed `pacman -Sy` to `dnf install -y`

#### Installation Scripts Converted

1. **1-yay.sh** → Fedora equivalent

   - Removed yay (Arch-specific AUR helper)
   - Added Development Tools group installation
   - Added note about AUR packages not being available

2. **2-identification.sh** → Fedora equivalent

   - Changed to install gum from GitHub releases (not available in Fedora repos)

3. **3-terminal.sh** → Fedora equivalent

   - `fd` → `fd-find`
   - `inetutils` → `net-tools`
   - `plocate` → `mlocate`

4. **hyprlandia.sh** → Fedora equivalent

   - Removed `hyprpolkitagent` and `hyprland-qtutils` (not available)
   - Added notes about missing packages

5. **desktop.sh** → Fedora equivalent

   - Removed several AUR packages not available in Fedora

6. **development.sh** → Fedora equivalent

   - `imagemagick` → `ImageMagick`
   - `mariadb-libs` → `mariadb-connector-c-devel`
   - `postgresql-libs` → `postgresql-devel`
   - `github-cli` → `gh`
   - Added note about mise installation

7. **fonts.sh** → Fedora equivalent

   - Converted all font packages to Fedora naming

8. **docker.sh** → No changes needed (same package names)

9. **theme.sh** → Fedora equivalent

   - `kvantum-qt5` → `kvantum`

10. **xtras.sh** → Fedora equivalent

    - Removed many proprietary packages with installation notes

11. **bluetooth.sh** → No changes needed

12. **power.sh** → No changes needed

13. **nvidia.sh** → Major overhaul for Fedora

    - Converted to use RPM Fusion repositories
    - Changed from mkinitcpio to dracut
    - Updated package names

14. **nvim.sh** → Fedora equivalent

    - `nvim` → `neovim`

15. **printer.sh** → No changes needed

16. **ruby.sh** → Fedora equivalent

    - Removed gcc-14 dependency
    - Added mise installation from source

17. **asdcontrol.sh** → No changes needed (compiles from source)

#### Migration Scripts Updated

All migration scripts updated to use `dnf` instead of `yay/pacman`.

#### System Configuration

- **install.sh**: Added Fedora prerequisites including RPM Fusion setup
- **README.md**: Updated to reflect Fedora adaptation

## Packages Not Available in Fedora Repos

The following packages were commented out or noted as requiring alternative installation:

### From AUR (Arch User Repository) - Not Available

- `yay` - Arch-specific AUR helper
- `gum` - Install from GitHub releases
- `clipse-bin` - AUR package
- `1password-beta` - Install from 1Password website
- `1password-cli` - Install from 1Password website
- `localsend-bin` - Install from GitHub releases or Flathub
- `lazydocker-bin` - Install from GitHub releases
- `obsidian-bin` - Install from Obsidian website or Flathub
- `hyprpolkitagent` - May need compilation from source
- `hyprland-qtutils` - May need compilation from source
- `wl-clip-persist` - May need compilation from source

### Alternative Installation Methods Needed

- **Signal Desktop**: Install from Flathub or Signal website
- **Spotify**: Install from Flathub or Spotify website
- **Dropbox CLI**: Install from Dropbox website
- **Zoom**: Install from Zoom website
- **Typora**: Install from Typora website
- **mise**: Install from GitHub releases or curl script

## Installation Prerequisites Added

1. **RPM Fusion Repositories**: Automatically enabled for multimedia and proprietary packages
2. **System Update**: Full system update before installation
3. **Development Tools**: Fedora's Development Tools group installed

## Notes for Users

1. Some Wayland/Hyprland packages may not be as up-to-date in Fedora compared to Arch
2. Consider using Flatpak for applications not available in Fedora repos
3. Some AUR packages may need manual compilation from source
4. The NVIDIA installation has been adapted for Fedora's RPM Fusion approach

## Testing Recommendations

1. Test on a fresh Fedora installation
2. Verify all Hyprland components work correctly
3. Check that all development tools are properly installed
4. Ensure theme switching works as expected
5. Test multimedia playback and hardware acceleration
