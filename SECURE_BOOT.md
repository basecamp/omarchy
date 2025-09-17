# Omarchy Secure Boot Automation

Automatically maintains EFI signature integrity and BLAKE2B hashes for Limine bootloader with UKI (Unified Kernel Image) setup.

## What it does

- Installs secure boot packages (sbctl, efitools, sbsigntools)
- Optionally creates custom secure boot keys
- Automatically signs EFI files after package updates
- Updates BLAKE2B hashes in limine.conf
- Prevents secure boot failures after kernel/bootloader updates

## Files included

- install/login/secure-boot-setup.sh - Initial secure boot key setup
- install/login/secure-boot.sh - Automation installer
- files/bin/omarchy-secure-boot-update.sh - Main automation script
- files/hooks/99-omarchy-secure-boot.hook - Pacman hook

## Installation Process

1. Package Installation: Installs required secure boot tools
2. Key Setup: Optionally creates and helps enroll custom keys
3. Automation Setup: Installs automation script and pacman hook

## Integration with Existing Hooks

Works seamlessly with Omarchy's existing hooks:
- 90-mkinitcpio-install.hook - Generates initramfs/UKI first
- 99-limine.hook - Updates Limine files second  
- 99-omarchy-secure-boot.hook - Signs updated files last

## Manual Usage

After installation, automation runs automatically. To run manually:

    sudo omarchy-secure-boot-update.sh

## Requirements

- Limine bootloader with UKI setup
- UEFI system with Secure Boot capability
- Administrative access for key management
