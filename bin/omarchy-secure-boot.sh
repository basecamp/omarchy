#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Omarchy Secure Boot Manager v1.3.1
# Complete secure boot automation for Limine + UKI with snapshot support
# Repository: https://github.com/peregrinus879/omarchy-secure-boot-manager
# ============================================================================

# ============================================================================
# SECTION 1: CONFIGURATION & CONSTANTS
# ============================================================================

# Script metadata
readonly VERSION="1.3.1"
readonly SCRIPT_NAME="omarchy-secure-boot.sh"

# System paths
readonly LIMINE_CONF="/boot/limine.conf"
readonly MACHINE_ID_FILE="/etc/machine-id"
readonly INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
readonly HOOK_PATH="/etc/pacman.d/hooks/zz-omarchy-secure-boot.hook"
readonly OLD_HOOK_PATH="/etc/pacman.d/hooks/99-omarchy-secure-boot.hook"
readonly SBCTL_HOOK="/usr/share/libalpm/hooks/zz-sbctl.hook"
readonly PACMAN_CONF="/etc/pacman.conf"

# Required packages for secure boot
readonly -a SB_PACKAGES=(
  "sbctl"
  "efitools"
  "sbsigntools"
)

# Behavior settings
readonly TIMEOUT_DURATION=15
readonly CONFIRM_BULK_CHANGES=true

# ============================================================================
# SECTION 2: OUTPUT COLORS & LOGGING FUNCTIONS
# ============================================================================

# Terminal colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions with consistent formatting
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

log_detail() {
  echo -e "${MAGENTA}[DETAIL]${NC} $*"
}

# ============================================================================
# SECTION 3: CORE UTILITY FUNCTIONS
# ============================================================================

# Get system machine ID for UKI identification
get_machine_id() {
  if [[ -f "$MACHINE_ID_FILE" ]]; then
    cat "$MACHINE_ID_FILE" | tr -d '\n'
  elif command -v systemd-machine-id-setup >/dev/null 2>&1; then
    systemd-machine-id-setup --print 2>/dev/null || echo ""
  else
    printf "%08x" "$(hostid)" 2>/dev/null || echo ""
  fi
}

# Create timestamped backup of limine.conf
backup_limine_conf() {
  local backup_name="${LIMINE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
  if sudo cp "$LIMINE_CONF" "$backup_name"; then
    log_info "Backup created: $backup_name"
    echo "$backup_name"
    return 0
  else
    log_error "Failed to backup limine.conf"
    return 1
  fi
}

# Require sudo authentication with single prompt
require_auth() {
  log_info "Authenticating for system changes..."
  if ! sudo -v; then
    log_error "Failed to authenticate"
    exit 1
  fi
}

# Extract SHA256 hash from snapshot filename
extract_sha256_from_filename() {
  local filename="$1"
  if [[ "$filename" =~ _sha256_([a-f0-9]{64}) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Get relative path for EFI file display
get_relative_efi_path() {
  local file="$1"
  local relpath="${file#/boot/}"
  echo "$relpath"
}

# ============================================================================
# SECTION 4: DISCOVERY FUNCTIONS
# ============================================================================

# Find all Linux-related EFI files dynamically
find_linux_efi_files() {
  local -a efi_files=()
  local file

  while IFS= read -r file; do
    # Skip Windows-related files
    if [[ "$file" =~ [Mm]icrosoft|[Ww]indows|bootmgfw ]]; then
      continue
    fi

    # Verify it's a regular file
    if [[ -f "$file" ]] && [[ ! -d "$file" ]]; then
      efi_files+=("$file")
    fi
  done < <(find /boot -type f -iname "*.efi" 2>/dev/null || true)

  printf '%s\n' "${efi_files[@]}"
}

# Find Windows Boot Manager across all mounted partitions
find_windows_bootmgr() {
  local bootmgr_path=""

  log_info "Searching for Windows Boot Manager..."

  # Define search locations
  local -a search_paths=(
    "/boot"
    "/boot/efi"
    "/efi"
    "/mnt/c"
    "/mnt/windows"
  )

  # Add all mounted FAT/NTFS partitions to search
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

  # Check for unmounted Windows partitions
  if [[ -z "$bootmgr_path" ]]; then
    local windows_parts
    windows_parts=$(lsblk -f -n -o NAME,FSTYPE,LABEL,MOUNTPOINT | grep -E "(ntfs|vfat)" | grep -v "/" | head -1 || true)
    if [[ -n "$windows_parts" ]]; then
      log_info "Found unmounted Windows partition(s). Consider mounting them to detect Windows."
    fi
  fi

  echo "$bootmgr_path"
}

# ============================================================================
# SECTION 5: VERIFICATION & CHECK FUNCTIONS
# ============================================================================

# Check if required packages are installed
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

# Check if secure boot keys exist
check_keys() {
  if [[ -f /usr/share/secureboot/keys/db/db.key ]] ||
    [[ -f /var/lib/sbctl/keys/db/db.key ]] ||
    [[ -d /var/lib/sbctl/keys ]] ||
    sbctl status 2>/dev/null | grep -q "Installed:"; then
    return 0
  else
    return 1
  fi
}

# Check for hash mismatches in current kernel and snapshots
check_hash_mismatches() {
  local mismatches=0
  local total=0

  # Check current kernel
  local machine_id
  machine_id=$(get_machine_id)
  local uki_file
  uki_file=$(find /boot -type f -name "${machine_id}_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)

  if [[ -f "$uki_file" ]]; then
    total=$((total + 1))
    local actual_hash
    actual_hash=$(b2sum "$uki_file" | awk '{print $1}')
    local uki_filename
    uki_filename=$(basename "$uki_file")

    if grep -qE "${uki_filename}" "$LIMINE_CONF"; then
      local config_hash
      config_hash=$(grep -E "${uki_filename}" "$LIMINE_CONF" | grep -v "limine_history" |
        sed -E 's/.*#([0-9a-f]{128})/\1/' 2>/dev/null | head -1 || true)

      if [[ "$actual_hash" != "$config_hash" ]]; then
        mismatches=$((mismatches + 1))
        log_warning "Current kernel: hash mismatch"
        echo -e "  File   : $uki_filename"
        echo -e "  Config : ${config_hash:0:32}..."
        echo -e "  Actual : ${actual_hash:0:32}..."
      fi
    fi
  fi

  # Check snapshots
  while IFS= read -r line; do
    if [[ "$line" =~ image_path:.*limine_history/([^#]+) ]]; then
      local snapshot_filename="${BASH_REMATCH[1]%%#*}"
      local sha256_part
      sha256_part=$(extract_sha256_from_filename "$snapshot_filename") || continue

      local efi_path
      efi_path=$(find /boot -type f -path "*/limine_history/*_sha256_${sha256_part}" 2>/dev/null | head -1)

      if [[ -f "$efi_path" ]]; then
        total=$((total + 1))
        local actual_hash
        actual_hash=$(b2sum "$efi_path" | awk '{print $1}')

        local config_hash=""
        if [[ "$line" =~ \#([a-f0-9]{128}) ]]; then
          config_hash="${BASH_REMATCH[1]}"
        fi

        if [[ "$actual_hash" != "$config_hash" ]]; then
          mismatches=$((mismatches + 1))
          log_warning "Snapshot: hash mismatch - SHA256_${sha256_part:0:16}..."
          echo -e "  Config : ${config_hash:0:32}..."
          echo -e "  Actual : ${actual_hash:0:32}..."
        fi
      fi
    fi
  done < <(grep "limine_history" "$LIMINE_CONF")

  if [[ $mismatches -eq 0 ]] && [[ $total -gt 0 ]]; then
    log_success "All $total UKI hashes match correctly"
  elif [[ $total -eq 0 ]]; then
    log_info "No UKI files found to check"
  else
    log_warning "$mismatches hash mismatch(es) found out of $total UKIs"
    log_info "Run '$SCRIPT_NAME --fix-hashes' to correct them"
  fi

  return $mismatches
}

# Verify EFI file signatures (quiet mode for hooks)
verify_signatures() {
  local quiet_mode="${1:-false}"
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)

  local all_verified=true
  local snapshot_count=0
  local current_count=0

  for file in "${efi_files[@]}"; do
    if [[ -f "$file" ]]; then
      local relpath=$(get_relative_efi_path "$file")

      # Categorize file type
      if [[ "$file" =~ limine_history ]]; then
        snapshot_count=$((snapshot_count + 1))
      elif [[ "$relpath" =~ _linux\.efi$ ]] && [[ ! "$file" =~ limine_history ]]; then
        current_count=$((current_count + 1))
      fi

      if ! timeout "$TIMEOUT_DURATION" sudo sbctl verify "$file" >/dev/null 2>&1; then
        all_verified=false
        if [[ "$quiet_mode" != "true" ]]; then
          echo "✗ $relpath"
        fi
      else
        if [[ "$quiet_mode" != "true" ]]; then
          echo "✓ $relpath"
        fi
      fi
    fi
  done

  if [[ $snapshot_count -gt 0 ]] && [[ "$quiet_mode" != "true" ]]; then
    log_info "Verified $snapshot_count snapshot(s) and $current_count current kernel(s)"
  fi

  if [[ "$all_verified" = true ]]; then
    log_success "All signatures verified"
    return 0
  else
    log_warning "Some signature issues detected"
    return 1
  fi
}

# ============================================================================
# SECTION 6: INSTALLATION & SETUP FUNCTIONS
# ============================================================================

# Configure pacman to never extract problematic sbctl hook
configure_pacman_noextract() {
  local noextract_entry="usr/share/libalpm/hooks/zz-sbctl.hook"

  if grep -q "NoExtract.*${noextract_entry}" "$PACMAN_CONF" 2>/dev/null; then
    log_info "Pacman already configured to skip sbctl hook"
    return 0
  fi

  log_info "Configuring pacman to prevent sbctl hook installation..."

  local backup_file="${PACMAN_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
  if ! sudo cp "$PACMAN_CONF" "$backup_file"; then
    log_error "Failed to backup pacman.conf"
    return 1
  fi
  log_info "Backup created: $backup_file"

  local has_noextract
  has_noextract=$(grep -n "^NoExtract" "$PACMAN_CONF" 2>/dev/null || echo "")

  if [[ -n "$has_noextract" ]]; then
    local line_num
    line_num=$(echo "$has_noextract" | head -1 | cut -d: -f1)

    if ! grep "^NoExtract" "$PACMAN_CONF" | grep -q "$noextract_entry"; then
      sudo sed -i "${line_num}s|$| ${noextract_entry}|" "$PACMAN_CONF"
      log_success "Added sbctl hook to existing NoExtract configuration"
    fi
  else
    local options_line
    options_line=$(grep -n "^\[options\]" "$PACMAN_CONF" | head -1 | cut -d: -f1)

    if [[ -n "$options_line" ]]; then
      sudo sed -i "${options_line}a NoExtract = ${noextract_entry}" "$PACMAN_CONF"
      log_success "Created NoExtract configuration for sbctl hook"
    else
      log_error "Could not find [options] section in pacman.conf"
      log_info "Please manually add to pacman.conf: NoExtract = ${noextract_entry}"
      return 1
    fi
  fi

  if grep -q "NoExtract.*${noextract_entry}" "$PACMAN_CONF"; then
    log_success "Pacman configuration updated successfully"
    return 0
  else
    log_error "Failed to update pacman configuration"
    return 1
  fi
}

# Remove NoExtract configuration (for uninstall)
remove_pacman_noextract() {
  local noextract_entry="usr/share/libalpm/hooks/zz-sbctl.hook"

  if ! grep -q "$noextract_entry" "$PACMAN_CONF" 2>/dev/null; then
    return 0
  fi

  log_info "Removing NoExtract configuration..."

  sudo cp "$PACMAN_CONF" "${PACMAN_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
  sudo sed -i "s| *${noextract_entry}||g" "$PACMAN_CONF"
  sudo sed -i '/^NoExtract[[:space:]]*=[[:space:]]*$/d' "$PACMAN_CONF"

  log_success "NoExtract configuration removed"
}

# Install required packages
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

# Install automation script and pacman hook
install_automation() {
  log_step "Installing Automation"

  # Clean install - remove existing files
  if [[ -f "$INSTALL_PATH" ]]; then
    log_info "Removing existing script..."
    sudo rm -f "$INSTALL_PATH"
  fi

  for hook in "$HOOK_PATH" "$OLD_HOOK_PATH"; do
    if [[ -f "$hook" ]]; then
      log_info "Removing existing hook: $(basename "$hook")"
      sudo rm -f "$hook"
    fi
  done

  # Install fresh script
  log_info "Installing script to $INSTALL_PATH"
  if ! sudo cp "$0" "$INSTALL_PATH"; then
    log_error "Failed to copy script"
    return 1
  fi

  if ! sudo chmod +x "$INSTALL_PATH"; then
    log_error "Failed to make script executable"
    return 1
  fi

  # Create pacman hook
  log_info "Creating pacman hook at $HOOK_PATH"
  if ! sudo tee "$HOOK_PATH" >/dev/null <<'HOOK_EOF'; then
# Omarchy Secure Boot Hook
# Automatically maintains EFI signatures after package updates
# This replaces the default sbctl hook functionality with Omarchy-aware signing

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
    log_error "Failed to create hook"
    return 1
  fi

  # Configure pacman NoExtract
  if ! configure_pacman_noextract; then
    log_warning "Could not configure pacman.conf automatically"
    log_info "The sbctl hook may reappear after sbctl updates"
  fi

  # Remove existing sbctl hook
  if [[ -f "$SBCTL_HOOK" ]]; then
    log_info "Removing incompatible sbctl hook..."
    if sudo rm -f "$SBCTL_HOOK"; then
      log_success "Removed sbctl hook - it won't return due to NoExtract"
    else
      log_warning "Could not remove sbctl hook - may cause error messages"
    fi
  fi

  # Verify installation
  if [[ -f "$INSTALL_PATH" ]] && [[ -x "$INSTALL_PATH" ]] && [[ -f "$HOOK_PATH" ]]; then
    log_success "Automation installed successfully"
    log_info "System will now automatically maintain secure boot after package updates"

    if grep -q "NoExtract.*zz-sbctl.hook" "$PACMAN_CONF" 2>/dev/null; then
      log_info "The problematic sbctl hook is permanently neutralized"
    fi

    return 0
  else
    log_error "Installation verification failed"
    return 1
  fi
}

# Create secure boot keys
create_keys() {
  log_step "Creating Secure Boot Keys"

  if check_keys; then
    log_warning "Secure boot keys already exist"
    timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || log_warning "Could not check sbctl status"
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

# Show enrollment instructions for BIOS setup
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

# ============================================================================
# SECTION 7: CORE OPERATIONS
# ============================================================================

# Sign all Linux EFI files
sign_files() {
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)

  if [[ ${#efi_files[@]} -eq 0 ]]; then
    log_warning "No Linux EFI files found to sign"
    return 1
  fi

  log_info "Found ${#efi_files[@]} Linux EFI files to process"

  local needs_signing=false
  for file in "${efi_files[@]}"; do
    if [[ ! -f "$file" ]] || [[ -d "$file" ]]; then
      continue
    fi

    local relpath=$(get_relative_efi_path "$file")
    log_info "Checking $relpath"
    if sudo sbctl verify "$file" >/dev/null 2>&1; then
      echo "    ✓ already signed"
    else
      echo "    → signing..."
      sudo sbctl sign -s "$file" >/dev/null 2>&1
      needs_signing=true
    fi
  done

  return $([ "$needs_signing" = true ] && echo 0 || echo 1)
}

# Update hash for current UKI file
update_hash() {
  local machine_id
  machine_id=$(get_machine_id)

  local uki_file
  uki_file=$(find /boot -type f -name "${machine_id}_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)

  if [[ -z "$uki_file" ]]; then
    uki_file=$(find /boot -type f -name "*_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)
  fi

  if [[ ! -f "$uki_file" ]] || [[ ! -f "$LIMINE_CONF" ]]; then
    return 1
  fi

  local new_hash current_hash
  new_hash=$(b2sum "$uki_file" | awk '{print $1}')
  local uki_filename
  uki_filename=$(basename "$uki_file")

  if grep -qE "${uki_filename}" "$LIMINE_CONF"; then
    current_hash=$(grep -E "${uki_filename}" "$LIMINE_CONF" | grep -v "limine_history" |
      sed -E 's/.*#([0-9a-f]{128})/\1/' 2>/dev/null | head -1)
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

# Process a single snapshot hash update
update_single_snapshot_hash() {
  local line_num="$1"
  local snapshot_filename="$2"
  local sha256_part="$3"

  local efi_path
  efi_path=$(find /boot -type f -path "*/limine_history/*_sha256_${sha256_part}" 2>/dev/null | head -1)

  if [[ ! -f "$efi_path" ]]; then
    log_warning "Snapshot file not found: SHA256 ${sha256_part:0:16}..."
    return 1
  fi

  local new_hash
  new_hash=$(b2sum "$efi_path" | awk '{print $1}')

  local escaped_filename
  escaped_filename=$(echo "$snapshot_filename" | sed 's/[[\.*^$()+?{|]/\\&/g')

  if sudo sed -i "${line_num}s|\(image_path:.*${escaped_filename}\)\(#[a-f0-9]*\)\?|\1#${new_hash}|" "$LIMINE_CONF"; then
    log_success "Updated line $line_num: SHA256 ${sha256_part:0:16}..."
    return 0
  else
    log_error "Failed to update line $line_num: SHA256 ${sha256_part:0:16}..."
    return 1
  fi
}

# Update snapshot UKI hashes after signing
update_snapshot_hashes() {
  log_step "Checking Snapshot UKI Hashes"

  local updated=0
  local checked=0
  local needs_update=0
  local -a updates_needed=()

  while IFS=: read -r line_num line_content; do
    if [[ "$line_content" =~ image_path:.*limine_history/([^#]+) ]]; then
      local snapshot_filename="${BASH_REMATCH[1]%%#*}"
      local sha256_part
      sha256_part=$(extract_sha256_from_filename "$snapshot_filename") || continue

      local efi_path
      efi_path=$(find /boot -type f -path "*/limine_history/*_sha256_${sha256_part}" 2>/dev/null | head -1)

      if [[ -f "$efi_path" ]]; then
        checked=$((checked + 1))
        local actual_hash
        actual_hash=$(b2sum "$efi_path" | awk '{print $1}')

        local config_hash=""
        if [[ "$line_content" =~ \#([a-f0-9]{128}) ]]; then
          config_hash="${BASH_REMATCH[1]}"
        fi

        if [[ "$actual_hash" != "$config_hash" ]]; then
          needs_update=$((needs_update + 1))
          updates_needed+=("${line_num}:${snapshot_filename}:${sha256_part}")
          log_detail "Line $line_num - SHA256_${sha256_part:0:16}...: hash mismatch"
          echo -e "    Config : ${config_hash:0:16}..."
          echo -e "    Actual : ${actual_hash:0:16}..."
        fi
      else
        log_warning "Snapshot file not found: SHA256 ${sha256_part:0:16}..."
      fi
    fi
  done < <(grep -n "limine_history/" "$LIMINE_CONF")

  if [[ $needs_update -eq 0 ]]; then
    log_success "All $checked snapshot hashes are already correct"
    return 0
  fi

  echo ""
  log_warning "Found $needs_update snapshot(s) with incorrect hashes out of $checked checked"

  if [[ "$CONFIRM_BULK_CHANGES" == "true" ]]; then
    read -p "Update snapshot hashes in limine.conf? (y/N): " update_confirm

    if [[ ! $update_confirm =~ ^[Yy]$ ]]; then
      log_info "Skipped snapshot hash updates"
      return 0
    fi
  fi

  backup_limine_conf

  log_info "Updating snapshot hashes..."

  for update_entry in "${updates_needed[@]}"; do
    IFS=: read -r line_num snapshot_filename sha256_part <<<"$update_entry"
    if update_single_snapshot_hash "$line_num" "$snapshot_filename" "$sha256_part"; then
      updated=$((updated + 1))
    fi
  done

  if [[ $updated -gt 0 ]]; then
    log_success "Successfully updated $updated snapshot hash(es)"
  else
    log_warning "No snapshot hashes were updated"
  fi
}

# Detect Windows version from available clues
detect_windows_version() {
  local windows_path="$1"
  local windows_version="Microsoft Windows"

  if lsblk -o LABEL 2>/dev/null | grep -qi "windows.*11\|win.*11"; then
    windows_version="Microsoft Windows 11"
  elif lsblk -o LABEL 2>/dev/null | grep -qi "windows.*10\|win.*10"; then
    windows_version="Microsoft Windows 10"
  elif find "$(dirname "$windows_path")" -name "*.mui" 2>/dev/null | grep -qi "windows.ui\|winui"; then
    windows_version="Microsoft Windows 11"
  fi

  echo "$windows_version"
}

# Check and add Windows entry to limine.conf
ensure_windows_entry() {
  log_step "Checking for Windows Boot Entry"

  if grep -qi "windows\|bootmgfw" "$LIMINE_CONF" 2>/dev/null; then
    log_success "Windows entry already exists in limine.conf"
    return 0
  fi

  local windows_path
  windows_path=$(find_windows_bootmgr)

  if [[ -z "$windows_path" ]]; then
    log_info "No Windows installation detected"
    return 0
  fi

  log_info "Found Windows Boot Manager at: $windows_path"

  local windows_version
  windows_version=$(detect_windows_version "$windows_path")
  log_info "Detected: $windows_version"

  local efi_path
  if [[ "$windows_path" =~ /boot/(.*) ]]; then
    efi_path="${BASH_REMATCH[1]}"
  elif [[ "$windows_path" =~ /efi/(.*) ]]; then
    efi_path="${BASH_REMATCH[1]}"
  else
    efi_path="$windows_path"
  fi

  local windows_entry="
# Windows Boot Manager
/Windows
    comment: $windows_version
    comment: order-priority=20
    protocol: efi_chainload
    image_path: boot():/${efi_path}"

  echo ""
  echo "The following entry will be added to limine.conf:"
  echo -e "${CYAN}$windows_entry${NC}"
  echo ""
  read -p "Add Windows entry to boot menu? (y/N): " add_windows

  if [[ $add_windows =~ ^[Yy]$ ]]; then
    backup_limine_conf
    echo "$windows_entry" | sudo tee -a "$LIMINE_CONF" >/dev/null
    log_success "Windows entry added to limine.conf"
  else
    log_info "Skipped adding Windows entry"
  fi
}

# ============================================================================
# SECTION 8: COMMAND IMPLEMENTATIONS
# ============================================================================

# Complete setup command
cmd_setup() {
  log_step "Starting Complete Secure Boot Setup"
  echo "Setting up secure boot for your Omarchy system..."
  echo ""

  if [[ $EUID -eq 0 ]]; then
    log_error "Don't run setup as root. The script will use sudo when needed."
    exit 1
  fi

  require_auth

  install_packages
  install_automation
  create_keys

  log_step "Initial EFI File Signing"
  if sign_files; then
    update_hash
  fi

  log_step "Checking for Hash Mismatches"
  if ! check_hash_mismatches; then
    log_info "Run '$SCRIPT_NAME --fix-hashes' to correct mismatches"
  fi

  log_step "Verifying Signatures"
  verify_signatures

  ensure_windows_entry

  echo ""
  if check_keys; then
    local sb_status
    sb_status=$(timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || echo "")

    if echo "$sb_status" | grep -q "Setup Mode.*✓ Enabled\|Setup Mode.*Enabled"; then
      show_enrollment_instructions
      echo ""
      log_info "Next step: $SCRIPT_NAME --enroll"
    elif echo "$sb_status" | grep -q "Secure Boot.*✓ Enabled\|Secure Boot.*Enabled"; then
      log_success "Keys are enrolled and secure boot is fully operational"
      log_info "System will automatically maintain secure boot from now on"
    else
      log_success "Keys exist but secure boot may be disabled"
      log_info "Enable Secure Boot in BIOS if not already enabled"
      log_info "Use '$SCRIPT_NAME --status' to check current state"
    fi
  else
    log_warning "No secure boot keys found"
    log_info "Create keys manually: sudo sbctl create-keys"
    log_info "Then run: $SCRIPT_NAME --enroll"
  fi

  log_success "Setup complete! Automation is active."
  echo ""
  log_info "Use '$SCRIPT_NAME --status' to check system state anytime"
}

# Enroll keys command
cmd_enroll() {
  log_step "Enrolling Secure Boot Keys"

  if ! check_keys; then
    log_error "No secure boot keys found"
    log_info "Create keys first: $SCRIPT_NAME --setup"
    log_info "Or manually: sudo sbctl create-keys"
    exit 1
  fi

  local sb_status
  sb_status=$(timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || echo "")

  if echo "$sb_status" | grep -q "Setup Mode.*✓ Enabled\|Setup Mode.*Enabled"; then
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
    timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || log_warning "Could not verify enrollment status"

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

# Update command (used by pacman hook)
cmd_update() {
  local machine_id
  machine_id=$(get_machine_id)

  if [[ -z "$machine_id" ]]; then
    log_error "Could not determine machine ID"
    exit 1
  fi

  log_info "Starting secure boot maintenance..."

  if [[ -t 0 ]]; then
    if ! sudo -v 2>/dev/null; then
      log_error "Failed to authenticate"
      exit 1
    fi
  fi

  local hash_updated=false
  local verification_passed=false

  # Sign files
  sign_files || true

  # Update hash
  if update_hash; then
    hash_updated=true
  fi

  # Verify signatures (quiet mode for hook output)
  if verify_signatures "true"; then
    verification_passed=true
  fi

  # Report results
  if [[ "$hash_updated" = true ]]; then
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

  exit 0
}

# Manual signing command
cmd_sign() {
  log_step "Manual File Signing"

  require_auth

  sign_files
  update_hash

  log_step "Checking for Hash Mismatches"
  check_hash_mismatches

  log_step "Verifying Signatures"
  verify_signatures

  log_success "Manual signing complete"
}

# Fix hash mismatches command
cmd_fix_hashes() {
  log_step "Fixing Hash Mismatches"

  require_auth

  local current_fixed=false
  if update_hash; then
    log_success "Fixed current kernel hash"
    current_fixed=true
  fi

  update_snapshot_hashes

  echo ""
  log_step "Verification"
  if check_hash_mismatches; then
    log_success "All hash mismatches have been resolved!"
  else
    log_warning "Some hash mismatches may still remain - check --status for details"
  fi
}

# Status command
cmd_status() {
  log_step "Secure Boot Status"

  if check_packages >/dev/null; then
    log_success "Required packages installed: ${SB_PACKAGES[*]}"
  else
    local missing_packages
    missing_packages=$(check_packages)
    log_warning "Missing packages: ${missing_packages[*]}"
  fi

  if check_keys; then
    log_success "Secure boot keys exist"
  else
    log_warning "No secure boot keys found"
  fi

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

  if grep -q "NoExtract.*zz-sbctl.hook" "$PACMAN_CONF" 2>/dev/null; then
    log_success "Conflicting sbctl hook permanently disabled"
  elif [[ -f "$SBCTL_HOOK" ]]; then
    log_warning "Conflicting sbctl hook present (may cause errors)"
  fi

  if grep -qi "windows\|bootmgfw" "$LIMINE_CONF" 2>/dev/null; then
    log_success "Windows boot entry configured"
  else
    local windows_path
    windows_path=$(find_windows_bootmgr)
    if [[ -n "$windows_path" ]]; then
      log_warning "Windows detected but not in boot menu (run --add-windows to add)"
    fi
  fi

  echo ""
  log_info "Linux EFI files found:"
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)
  local snapshot_count=0
  for file in "${efi_files[@]}"; do
    local relpath=$(get_relative_efi_path "$file")
    if [[ "$file" =~ limine_history ]]; then
      echo "  - $relpath"
      snapshot_count=$((snapshot_count + 1))
    else
      echo "  - $relpath"
    fi
  done
  if [[ $snapshot_count -gt 0 ]]; then
    log_info "Including $snapshot_count snapshot UKI(s)"
  fi

  if command -v sbctl >/dev/null 2>&1; then
    echo ""
    log_info "Authenticating to check detailed status..."
    if sudo -v 2>/dev/null; then
      timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || log_warning "sbctl status timed out or failed"

      echo ""
      log_step "Verifying EFI File Signatures"
      verify_signatures

      log_step "Checking for Hash Mismatches"
      check_hash_mismatches
    else
      log_warning "Authentication failed - skipping detailed status"
    fi
  else
    log_warning "sbctl not found - install packages first"
  fi
}

# Add Windows entry command
cmd_add_windows() {
  require_auth
  ensure_windows_entry
}

# Clean uninstall command
cmd_uninstall() {
  log_step "Uninstalling Omarchy Secure Boot Manager"

  echo "This will remove:"
  echo "  - The automation script from $INSTALL_PATH"
  echo "  - The pacman hook from $HOOK_PATH"
  echo "  - NoExtract configuration from pacman.conf"
  echo ""
  echo "This will NOT remove:"
  echo "  - Your secure boot keys"
  echo "  - Any EFI signatures"
  echo "  - Limine configuration changes"
  echo ""
  read -p "Continue with uninstall? (y/N): " confirm_uninstall

  if [[ ! $confirm_uninstall =~ ^[Yy]$ ]]; then
    log_info "Uninstall cancelled"
    return 0
  fi

  require_auth

  local removed_items=0

  if [[ -f "$INSTALL_PATH" ]]; then
    if sudo rm -f "$INSTALL_PATH"; then
      log_success "Removed script"
      removed_items=$((removed_items + 1))
    else
      log_error "Failed to remove script"
    fi
  else
    log_info "Script not found (already removed?)"
  fi

  for hook in "$HOOK_PATH" "$OLD_HOOK_PATH"; do
    if [[ -f "$hook" ]]; then
      if sudo rm -f "$hook"; then
        log_success "Removed hook: $(basename "$hook")"
        removed_items=$((removed_items + 1))
      else
        log_error "Failed to remove hook: $(basename "$hook")"
      fi
    fi
  done

  if grep -q "NoExtract.*zz-sbctl.hook" "$PACMAN_CONF" 2>/dev/null; then
    remove_pacman_noextract
    removed_items=$((removed_items + 1))
  fi

  if [[ $removed_items -gt 0 ]]; then
    log_success "Uninstall complete ($removed_items items removed)"
    echo ""
    log_warning "Note: The sbctl hook may be reinstalled on next sbctl update"
    log_info "Your secure boot keys and signatures remain intact"
  else
    log_info "Nothing to uninstall"
  fi
}

# ============================================================================
# SECTION 9: HELP & MAIN EXECUTION
# ============================================================================

# Show usage information
show_usage() {
  echo -e "${BOLD}Omarchy Secure Boot Manager v${VERSION}${NC}"
  echo "Complete setup and maintenance for Limine + UKI secure boot with snapshot support"
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
  echo "  --fix-hashes   Fix all hash mismatches (current + snapshots)"
  echo "  --status       Show secure boot status and verification"
  echo ""
  echo -e "${BOLD}MANAGEMENT:${NC}"
  echo "  --uninstall    Remove automation (keeps keys and signatures)"
  echo "  --help         Show this help message"
  echo ""
  echo -e "${BOLD}TYPICAL WORKFLOW:${NC}"
  echo "  1. $0 --setup"
  echo "  2. Reboot → BIOS → Clear keys → Setup Mode → Reboot"
  echo "  3. $0 --enroll"
  echo "  4. Reboot → BIOS → Enable Secure Boot"
  echo ""
  echo -e "${BOLD}KEY FEATURES v${VERSION}:${NC}"
  echo "  • Fixed pacman hook exit status for clean updates"
  echo "  • Neutralizes conflicting sbctl hook permanently"
  echo "  • Robust setup that always installs automation"
  echo "  • Snapshot hash management for complex naming schemes"
  echo "  • Clean uninstall option that preserves security"
  echo ""
}

# Main function - command dispatcher
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
  --fix-hashes)
    cmd_fix_hashes
    ;;
  --status)
    cmd_status
    ;;
  --add-windows)
    cmd_add_windows
    ;;
  --uninstall)
    cmd_uninstall
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

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

main "$@"
