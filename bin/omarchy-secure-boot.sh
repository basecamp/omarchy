#!/usr/bin/env bash
set -euo pipefail

# Omarchy Secure Boot Manager v1.1
# Complete secure boot automation for Limine + UKI
# Repository: https://github.com/peregrinus879/omarchy-secure-boot-manager

# Configuration
readonly LIMINE_CONF="/boot/limine.conf"
readonly MACHINE_ID_FILE="/etc/machine-id"
readonly SCRIPT_NAME="omarchy-secure-boot.sh"
readonly INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
readonly HOOK_PATH="/etc/pacman.d/hooks/99-omarchy-secure-boot.hook"

# Required packages
readonly -a SB_PACKAGES=(
  "sbctl"
  "efitools"
  "sbsigntools"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
  echo -e "\n${CYAN}${BOLD}=== $* ===${NC}"
}

# Utility functions
get_machine_id() {
  if [[ -f "$MACHINE_ID_FILE" ]]; then
    cat "$MACHINE_ID_FILE" | tr -d '\n'
  elif command -v systemd-machine-id-setup >/dev/null 2>&1; then
    systemd-machine-id-setup --print 2>/dev/null || echo ""
  else
    printf "%08x" "$(hostid)" 2>/dev/null || echo ""
  fi
}

# NEW: Find all Linux-related EFI files dynamically
find_linux_efi_files() {
  local -a efi_files=()
  local file

  # Search for all .efi files in /boot, excluding Windows-related ones
  # Use -type f to ensure we only get regular files, not directories
  while IFS= read -r file; do
    # Skip Windows-related files
    if [[ "$file" =~ [Mm]icrosoft|[Ww]indows|bootmgfw ]]; then
      continue
    fi

    # Double-check it's a regular file (not directory, symlink, etc.)
    if [[ -f "$file" ]] && [[ ! -d "$file" ]]; then
      efi_files+=("$file")
    fi
  done < <(find /boot -type f -iname "*.efi" 2>/dev/null || true)

  # Return the array
  printf '%s\n' "${efi_files[@]}"
}

# NEW: Find Windows Boot Manager (searches all mounted partitions)
find_windows_bootmgr() {
  local bootmgr_path=""

  # Search all mounted partitions for Windows Boot Manager
  log_info "Searching for Windows Boot Manager..."

  # Method 1: Check common mount points
  local -a search_paths=(
    "/boot"
    "/boot/efi"
    "/efi"
    "/mnt/c"
    "/mnt/windows"
  )

  # Method 2: Find all mounted FAT/NTFS partitions
  while IFS= read -r mount_point; do
    if [[ -n "$mount_point" ]] && [[ ! " ${search_paths[@]} " =~ " ${mount_point} " ]]; then
      search_paths+=("$mount_point")
    fi
  done < <(findmnt -t vfat,ntfs,ntfs3 -n -o TARGET 2>/dev/null || true)

  # Search each location for bootmgfw.efi
  for search_dir in "${search_paths[@]}"; do
    if [[ -d "$search_dir" ]]; then
      local found
      found=$(find "$search_dir" -type f -ipath "*/Microsoft/Boot/bootmgfw.efi" 2>/dev/null | head -1 || true)
      if [[ -n "$found" ]] && [[ -f "$found" ]]; then
        bootmgr_path="$found"
        log_info "Found Windows at: $bootmgr_path"
        break
      fi
    fi
  done

  # If still not found, check if Windows partition needs mounting
  if [[ -z "$bootmgr_path" ]]; then
    # Check if there are unmounted Windows partitions
    local windows_parts
    windows_parts=$(lsblk -f -n -o NAME,FSTYPE,LABEL,MOUNTPOINT | grep -E "(ntfs|vfat)" | grep -v "/" | head -1 || true)
    if [[ -n "$windows_parts" ]]; then
      log_info "Found unmounted Windows partition(s). Consider mounting them to detect Windows."
    fi
  fi

  echo "$bootmgr_path"
}

# NEW: Check and add Windows entry to limine.conf
ensure_windows_entry() {
  log_step "Checking for Windows Boot Entry"

  # Check if Windows entry already exists
  if grep -qi "windows\|bootmgfw" "$LIMINE_CONF" 2>/dev/null; then
    log_success "Windows entry already exists in limine.conf"
    return 0
  fi

  # Find Windows Boot Manager
  local windows_path
  windows_path=$(find_windows_bootmgr)

  if [[ -z "$windows_path" ]]; then
    log_info "No Windows installation detected"
    return 0
  fi

  log_info "Found Windows Boot Manager at: $windows_path"

  # Convert absolute path to relative EFI path
  local efi_path
  if [[ "$windows_path" =~ /boot/(.*) ]]; then
    efi_path="${BASH_REMATCH[1]}"
  elif [[ "$windows_path" =~ /efi/(.*) ]]; then
    efi_path="${BASH_REMATCH[1]}"
  else
    efi_path="$windows_path"
  fi

  # Determine if it's on the same partition or different
  local protocol="boot()"
  if [[ "$windows_path" =~ ^/efi/ ]]; then
    # Different partition mounting
    protocol="boot()"
  fi

  # Create Windows entry
  local windows_entry="
# Windows Boot Manager
/Windows
    comment: Microsoft Windows 11
    comment: order-priority=20
    protocol: efi_chainload
    image_path: ${protocol}:/${efi_path}"

  # Ask for confirmation before adding
  echo ""
  echo "The following entry will be added to limine.conf:"
  echo -e "${CYAN}$windows_entry${NC}"
  echo ""
  read -p "Add Windows entry to boot menu? (y/N): " add_windows

  if [[ $add_windows =~ ^[Yy]$ ]]; then
    # Backup limine.conf
    sudo cp "$LIMINE_CONF" "${LIMINE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

    # Add entry to limine.conf
    echo "$windows_entry" | sudo tee -a "$LIMINE_CONF" >/dev/null
    log_success "Windows entry added to limine.conf"
    log_info "Backup saved to ${LIMINE_CONF}.backup.*"
  else
    log_info "Skipped adding Windows entry"
  fi
}

check_packages() {
  local missing_packages=()
  for package in "${SB_PACKAGES[@]}"; do
    if ! pacman -Qi "$package" >/dev/null 2>&1; then
      missing_packages+=("$package")
    fi
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    echo "${missing_packages[@]}"
    return 1
  fi
  return 0
}

check_keys() {
  # Check multiple possible key locations
  if [[ -f /usr/share/secureboot/keys/db/db.key ]] ||
    [[ -f /var/lib/sbctl/keys/db/db.key ]] ||
    [[ -d /var/lib/sbctl/keys ]] ||
    sbctl status 2>/dev/null | grep -q "Installed:"; then
    return 0
  else
    return 1
  fi
}

# Setup functions
install_packages() {
  log_step "Installing Secure Boot Packages"

  local missing_packages
  if missing_packages=$(check_packages); then
    log_success "All required packages already installed"
    return 0
  fi

  log_info "Installing: ${missing_packages[*]}"
  sudo pacman -Syu --needed "${SB_PACKAGES[@]}"

  if check_packages >/dev/null; then
    log_success "Packages installed successfully"
  else
    log_error "Failed to install packages"
    exit 1
  fi
}

install_automation() {
  log_step "Installing Automation"

  # Clean install - remove any existing files first
  if [[ -f "$INSTALL_PATH" ]]; then
    log_info "Removing existing script..."
    sudo rm -f "$INSTALL_PATH"
  fi

  if [[ -f "$HOOK_PATH" ]]; then
    log_info "Removing existing hook..."
    sudo rm -f "$HOOK_PATH"
  fi

  # Install fresh script
  log_info "Installing script to $INSTALL_PATH"
  sudo cp "$0" "$INSTALL_PATH"
  sudo chmod +x "$INSTALL_PATH"

  # Create and install fresh hook
  log_info "Creating pacman hook at $HOOK_PATH"
  sudo tee "$HOOK_PATH" >/dev/null <<'HOOK_EOF'
# Omarchy Secure Boot Hook
# Automatically maintains EFI signatures after package updates

[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Omarchy: Secure boot maintenance
When = PostTransaction
Exec = /usr/local/bin/omarchy-secure-boot.sh --update
Depends = sbctl
HOOK_EOF

  # Verify installation
  if [[ -f "$INSTALL_PATH" ]] && [[ -x "$INSTALL_PATH" ]] && [[ -f "$HOOK_PATH" ]]; then
    log_success "Automation installed successfully"
    log_info "System will now automatically maintain secure boot after package updates"
  else
    log_error "Failed to install automation properly"
    exit 1
  fi
}

create_keys() {
  log_step "Creating Secure Boot Keys"

  if check_keys; then
    log_warning "Secure boot keys already exist"
    timeout 10 sudo sbctl status 2>/dev/null || log_warning "Could not check sbctl status"
    echo ""
    read -p "Recreate keys? This will invalidate existing signatures (y/N): " recreate
    if [[ ! $recreate =~ ^[Yy]$ ]]; then
      log_info "Keeping existing keys"
      return 0
    fi
    log_info "Removing existing keys..."
    sudo rm -rf /usr/share/secureboot/keys/ 2>/dev/null || true
  fi

  log_info "Creating secure boot keys..."
  if sudo sbctl create-keys; then
    log_success "Keys created successfully"
  else
    log_error "Failed to create keys - continuing with setup anyway"
    log_info "You can create keys manually later: sudo sbctl create-keys"
    return 1
  fi
}

show_enrollment_instructions() {
  echo ""
  echo -e "${BOLD}${YELLOW}🔐 SECURE BOOT KEY ENROLLMENT REQUIRED${NC}"
  echo -e "${YELLOW}=============================================${NC}"
  echo -e "${YELLOW}Your secure boot keys have been created but need to be enrolled.${NC}"
  echo ""
  echo -e "${CYAN}Next steps:${NC}"
  echo -e "  ${BOLD}1.${NC} Reboot your system"
  echo -e "  ${BOLD}2.${NC} Enter BIOS/UEFI setup (usually F2, F12, or Del during boot)"
  echo -e "  ${BOLD}3.${NC} Navigate to Secure Boot settings"
  echo -e "  ${BOLD}4.${NC} Clear/Delete all existing keys (enter Setup Mode)"
  echo -e "  ${BOLD}5.${NC} Save changes and reboot back to Linux"
  echo -e "  ${BOLD}6.${NC} Run: ${CYAN}$SCRIPT_NAME --enroll${NC}"
  echo ""
  echo -e "${YELLOW}=============================================${NC}"

  # Create helper script for convenience
  cat >/tmp/omarchy-sb-enroll.sh <<'ENROLL_EOF'
#!/bin/bash
echo "🔐 Enrolling Omarchy secure boot keys..."
sudo sbctl enroll-keys -m -f
echo ""
echo "✅ Keys enrolled! Status:"
sudo sbctl status
echo ""
echo "🔄 Now reboot and enable Secure Boot in BIOS."
ENROLL_EOF
  chmod +x /tmp/omarchy-sb-enroll.sh

  echo -e "${CYAN}Alternative: Run the helper script after BIOS setup:${NC}"
  echo -e "  ${BOLD}/tmp/omarchy-sb-enroll.sh${NC}"
  echo ""
}

# ENHANCED: Sign only actual EFI files (not directories)
sign_files() {
  local machine_id
  machine_id=$(get_machine_id)

  # Get all Linux-related EFI files dynamically
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)

  if [[ ${#efi_files[@]} -eq 0 ]]; then
    log_warning "No Linux EFI files found to sign"
    return 1
  fi

  log_info "Found ${#efi_files[@]} Linux EFI files to process"

  # Sign files that need signing
  local needs_signing=false
  for file in "${efi_files[@]}"; do
    # Triple-check: it's a file, not a directory, and exists
    if [[ ! -f "$file" ]] || [[ -d "$file" ]]; then
      continue
    fi

    log_info "Checking $(basename "$file")"
    if sbctl verify "$file" >/dev/null 2>&1; then
      echo -e "    ${GREEN}[ok]${NC} already signed"
    else
      echo -e "    ${YELLOW}[signing]${NC} $(basename "$file")"
      sudo sbctl sign -s "$file"
      needs_signing=true
    fi
  done

  return $([ "$needs_signing" = true ] && echo 0 || echo 1)
}

# ENHANCED: Update hash for UKI file
update_hash() {
  local machine_id
  machine_id=$(get_machine_id)

  # Find the UKI file (ensure it's a regular file)
  local uki_file
  uki_file=$(find /boot -type f -name "${machine_id}_linux.efi" 2>/dev/null | head -1 || true)

  if [[ -z "$uki_file" ]]; then
    # Try to find any UKI file (still ensuring it's a regular file)
    uki_file=$(find /boot -type f -name "*_linux.efi" 2>/dev/null | head -1 || true)
  fi

  if [[ ! -f "$uki_file" ]] || [[ ! -f "$LIMINE_CONF" ]]; then
    return 1
  fi

  local new_hash current_hash
  new_hash=$(b2sum "$uki_file" | awk '{print $1}')
  local uki_filename
  uki_filename=$(basename "$uki_file")

  if grep -qE "${uki_filename}" "$LIMINE_CONF"; then
    current_hash=$(grep -E "${uki_filename}" "$LIMINE_CONF" |
      sed -E 's/.*#([0-9a-f]{128})/\1/' 2>/dev/null || true)
  fi

  if [[ "$new_hash" != "$current_hash" ]]; then
    log_info "Updating BLAKE2B hash for $uki_filename in limine.conf"
    sudo sed -i -E "s|(image_path:.*${uki_filename})(#.*)?$|\1#${new_hash}|" \
      "$LIMINE_CONF"
    log_success "Hash updated: ${new_hash:0:16}..."
    return 0
  else
    return 1
  fi
}

verify_signatures() {
  # Get all Linux EFI files to verify (files only, not directories)
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)

  local all_verified=true
  local verification_output=""

  # Verify each file individually
  for file in "${efi_files[@]}"; do
    if [[ -f "$file" ]]; then
      local filename=$(basename "$file")
      local dir_hint=""

      # Add directory hint for duplicate filenames
      if [[ "$filename" == "BOOTX64.EFI" ]]; then
        if [[ "$file" =~ /limine/ ]]; then
          dir_hint=" (limine)"
        elif [[ "$file" =~ /BOOT/ ]]; then
          dir_hint=" (BOOT)"
        fi
      fi

      if timeout 5 sudo sbctl verify "$file" >/dev/null 2>&1; then
        verification_output+="✓ ${filename}${dir_hint}\n"
      else
        verification_output+="✗ ${filename}${dir_hint}\n"
        all_verified=false
      fi
    fi
  done

  if [[ -n "$verification_output" ]]; then
    echo -e "$verification_output"
  fi

  if [[ "$all_verified" = true ]]; then
    log_success "All signatures verified"
    return 0
  else
    log_warning "Some signature issues detected"
    return 1
  fi
}

# Main command implementations
cmd_setup() {
  log_step "Starting Complete Secure Boot Setup"
  echo "Setting up secure boot for your Omarchy system..."
  echo ""

  # Check not running as root
  if [[ $EUID -eq 0 ]]; then
    log_error "Don't run setup as root. The script will use sudo when needed."
    exit 1
  fi

  # Authenticate sudo upfront (like pacman -Syu)
  log_info "Authenticating for system changes..."
  if ! sudo -v; then
    log_error "Failed to authenticate"
    exit 1
  fi

  # Step 1: Install packages (critical foundation)
  install_packages

  # Step 2: ALWAYS install automation FIRST (before anything can fail/exit)
  install_automation

  # Step 3: Create keys (optional - setup continues regardless)
  create_keys

  # Step 4: Always run initial signing and verification
  log_step "Initial EFI File Signing"
  local files_signed=false
  if sign_files; then
    files_signed=true
    update_hash
  fi
  verify_signatures

  # Step 5: Check and add Windows entry if needed
  ensure_windows_entry

  # Step 6: Smart completion messages based on actual state
  echo ""
  if check_keys; then
    # Check if we're in Setup Mode (need enrollment) or keys are already enrolled
    local sb_status
    sb_status=$(timeout 10 sudo sbctl status 2>/dev/null || echo "")

    if echo "$sb_status" | grep -q "Setup Mode.*✓ Enabled\|Setup Mode.*Enabled"; then
      # Setup Mode is ENABLED = need to enroll keys
      show_enrollment_instructions
      echo ""
      log_info "Next step: $SCRIPT_NAME --enroll"
    elif echo "$sb_status" | grep -q "Secure Boot.*✓ Enabled\|Secure Boot.*Enabled"; then
      # Secure Boot is ENABLED = everything is working!
      log_success "✅ Keys are enrolled and secure boot is fully operational!"
      log_info "System will automatically maintain secure boot from now on"
    else
      # Can't determine status or secure boot is disabled
      log_success "✅ Keys exist but secure boot may be disabled"
      log_info "Enable Secure Boot in BIOS if not already enabled"
      log_info "Use '$SCRIPT_NAME --status' to check current state"
    fi
  else
    log_warning "⚠️  No secure boot keys found"
    log_info "Create keys manually: sudo sbctl create-keys"
    log_info "Then run: $SCRIPT_NAME --enroll"
  fi

  log_success "Setup complete! Automation is active."
  echo ""
  log_info "Use '$SCRIPT_NAME --status' to check system state anytime"
}

cmd_enroll() {
  log_step "Enrolling Secure Boot Keys"

  if ! check_keys; then
    log_error "No secure boot keys found"
    log_info "Create keys first: $SCRIPT_NAME --setup"
    log_info "Or manually: sudo sbctl create-keys"
    exit 1
  fi

  # Check setup mode (but don't fail if we can't determine it)
  local setup_mode_check=false
  local sb_status
  sb_status=$(timeout 10 sudo sbctl status 2>/dev/null || echo "")

  if echo "$sb_status" | grep -q "Setup Mode.*✓ Enabled\|Setup Mode.*Enabled"; then
    setup_mode_check=true
    log_info "System is in Setup Mode - ready for enrollment"
  elif echo "$sb_status" | grep -q "Setup Mode.*✓ Disabled\|Setup Mode.*Disabled"; then
    log_warning "Keys appear to be already enrolled (Setup Mode is disabled)"
    log_info "Your secure boot setup may already be complete"
    echo ""
    read -p "Continue with key enrollment anyway? (y/N): " continue_enroll
    if [[ ! $continue_enroll =~ ^[Yy]$ ]]; then
      log_info "Key enrollment cancelled"
      return 0
    fi
  else
    log_warning "Cannot determine Setup Mode status"
    echo ""
    echo "To enter Setup Mode:"
    echo "  1. Reboot and enter BIOS/UEFI setup"
    echo "  2. Find Secure Boot settings"
    echo "  3. Clear/Delete all existing keys"
    echo "  4. Save and reboot"
    echo ""
    read -p "Continue with key enrollment anyway? (y/N): " continue_enroll
    if [[ ! $continue_enroll =~ ^[Yy]$ ]]; then
      log_info "Key enrollment cancelled"
      return 0
    fi
  fi

  log_info "Enrolling secure boot keys..."
  if sudo sbctl enroll-keys -m -f; then
    log_success "Keys enrolled successfully"
    timeout 10 sudo sbctl status 2>/dev/null || log_warning "Could not verify enrollment status"

    echo ""
    echo -e "${BOLD}${GREEN}🔐 FINAL STEP: Enable Secure Boot${NC}"
    echo -e "${GREEN}=================================${NC}"
    echo -e "  ${BOLD}1.${NC} Reboot your system"
    echo -e "  ${BOLD}2.${NC} Enter BIOS/UEFI setup"
    echo -e "  ${BOLD}3.${NC} Enable Secure Boot"
    echo -e "  ${BOLD}4.${NC} Save and reboot"
    echo ""
    echo -e "${GREEN}After that, automatic maintenance will handle everything!${NC}"
  else
    log_error "Key enrollment failed"
    log_info "This may happen if:"
    log_info "  - System is not in Setup Mode"
    log_info "  - EFI variables are not accessible"
    log_info "  - Firmware does not support custom keys"
    exit 1
  fi
}

cmd_update() {
  # Called by pacman hook and for manual updates
  local machine_id
  machine_id=$(get_machine_id)

  if [[ -z "$machine_id" ]]; then
    log_error "Could not determine machine ID"
    exit 1
  fi

  log_info "Starting secure boot maintenance..."

  # For manual runs (not hook), authenticate upfront
  if [[ -t 0 ]]; then # Check if running interactively
    if ! sudo -v 2>/dev/null; then
      log_error "Failed to authenticate"
      exit 1
    fi
  fi

  local files_signed=false
  local hash_updated=false
  local verification_passed=false

  # Sign files if needed
  if sign_files; then
    files_signed=true
  fi

  # Update hash if needed
  if update_hash; then
    hash_updated=true
  fi

  # Always run verification
  if verify_signatures; then
    verification_passed=true
  fi

  # Report results
  if [[ "$files_signed" = true ]] || [[ "$hash_updated" = true ]]; then
    if [[ "$verification_passed" = true ]]; then
      log_success "Maintenance complete - all signatures verified"
    else
      log_warning "Maintenance complete but some verification issues remain"
    fi
  else
    if [[ "$verification_passed" = true ]]; then
      log_info "No changes needed - everything up to date"
    else
      log_warning "No changes made but verification issues detected"
    fi
  fi
}

cmd_status() {
  log_step "Secure Boot Status"

  # Check packages
  if check_packages >/dev/null; then
    log_success "Required packages installed: ${SB_PACKAGES[*]}"
  else
    local missing_packages
    missing_packages=$(check_packages)
    log_warning "Missing packages: ${missing_packages[*]}"
  fi

  # Check keys
  if check_keys; then
    log_success "Secure boot keys exist"
  else
    log_warning "No secure boot keys found"
  fi

  # Check automation
  if [[ -f "$INSTALL_PATH" ]] && [[ -f "$HOOK_PATH" ]]; then
    log_success "Automation installed and active"
  else
    log_warning "Automation not installed"
    if [[ ! -f "$INSTALL_PATH" ]]; then
      echo "  Missing: $INSTALL_PATH"
    fi
    if [[ ! -f "$HOOK_PATH" ]]; then
      echo "  Missing: $HOOK_PATH"
    fi
  fi

  # Check Windows entry
  if grep -qi "windows\|bootmgfw" "$LIMINE_CONF" 2>/dev/null; then
    log_success "Windows boot entry configured"
  else
    local windows_path
    windows_path=$(find_windows_bootmgr)
    if [[ -n "$windows_path" ]]; then
      log_warning "Windows detected but not in boot menu (run --add-windows to add)"
    fi
  fi

  # List found EFI files
  echo ""
  log_info "Linux EFI files found:"
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)
  for file in "${efi_files[@]}"; do
    echo "  - $(basename "$file") ($(dirname "$file"))"
  done

  # Show sbctl status with timeout (needs authentication)
  if command -v sbctl >/dev/null 2>&1; then
    echo ""
    log_info "Authenticating to check detailed status..."
    if sudo -v 2>/dev/null; then
      timeout 15 sudo sbctl status 2>/dev/null || log_warning "sbctl status timed out or failed"
      echo ""
      log_info "Verifying EFI file signatures:"
      verify_signatures
    else
      log_warning "Authentication failed - skipping detailed status"
    fi
  else
    log_warning "sbctl not found - install packages first"
  fi
}

cmd_sign() {
  log_step "Manual File Signing"

  # Authenticate upfront
  log_info "Authenticating for system changes..."
  if ! sudo -v; then
    log_error "Failed to authenticate"
    exit 1
  fi

  sign_files
  update_hash
  verify_signatures
  log_success "Manual signing complete"
}

# NEW: Command to add Windows entry
cmd_add_windows() {
  log_info "Authenticating for system changes..."
  if ! sudo -v; then
    log_error "Failed to authenticate"
    exit 1
  fi
  ensure_windows_entry
}

show_usage() {
  echo -e "${BOLD}Omarchy Secure Boot Manager v1.1${NC}"
  echo "Complete setup and maintenance for Limine + UKI secure boot"
  echo ""
  echo -e "${BOLD}USAGE:${NC}"
  echo "  $0 [COMMAND]"
  echo ""
  echo -e "${BOLD}SETUP COMMANDS:${NC}"
  echo "  --setup        Complete setup for new systems (robust)"
  echo "  --enroll       Enroll keys after BIOS setup"
  echo "  --add-windows  Add Windows entry to boot menu"
  echo ""
  echo -e "${BOLD}MAINTENANCE COMMANDS:${NC}"
  echo "  --update       Update signatures and hashes (used by pacman hook)"
  echo "  --sign         Manual signing of all EFI files"
  echo "  --status       Show secure boot status and verification"
  echo ""
  echo -e "${BOLD}HELP:${NC}"
  echo "  --help         Show this help message"
  echo ""
  echo -e "${BOLD}TYPICAL WORKFLOW:${NC}"
  echo "  1. $0 --setup"
  echo "  2. Reboot → BIOS → Clear keys → Setup Mode → Reboot"
  echo "  3. $0 --enroll"
  echo "  4. Reboot → BIOS → Enable Secure Boot"
  echo ""
  echo -e "${BOLD}NEW FEATURES (v1.1):${NC}"
  echo "  • Dynamic discovery of all Linux EFI files"
  echo "  • Windows detection across all mounted partitions"
  echo "  • Enhanced file verification (no directory operations)"
  echo "  • Upfront authentication (single password prompt)"
  echo "  • Individual file verification with status display"
  echo ""
  echo -e "${BOLD}NOTE:${NC} After setup, maintenance is automatic via pacman hooks."
  echo "      The hook uses --update for minimal, fast maintenance."
  echo "      Use --status to check system state anytime."
  echo ""
}

# Main function
main() {
  case "${1:-}" in
  --setup)
    cmd_setup
    ;;
  --enroll)
    cmd_enroll
    ;;
  --update)
    cmd_update
    ;;
  --sign)
    cmd_sign
    ;;
  --status)
    cmd_status
    ;;
  --add-windows)
    cmd_add_windows
    ;;
  --help | -h | "")
    show_usage
    ;;
  *)
    log_error "Unknown command: $1"
    echo ""
    show_usage
    exit 1
    ;;
  esac
}

# Execute main function
main "$@"
