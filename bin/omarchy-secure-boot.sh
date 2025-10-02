#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Omarchy Secure Boot Manager v1.4.0
# Complete secure boot automation for Limine + UKI with snapshot support
# Repository: https://github.com/peregrinus879/omarchy-secure-boot-manager
# ============================================================================

# ============================================================================
# SECTION 1: CONFIGURATION & CONSTANTS
# ============================================================================

# Script metadata
readonly VERSION="1.4.0"
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

# Global state management
BACKUP_FILES=()
CLEANUP_NEEDED=false

# Performance optimization - hash caching
declare -A HASH_CACHE
declare -A FILE_MTIME_CACHE

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
    BACKUP_FILES+=("$backup_name")
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
  echo "${file#/boot/}"
}

# Get file modification time for cache validation
get_file_mtime() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
}

# Calculate BLAKE2B hash of a file (direct calculation)
calculate_file_hash() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  b2sum "$file" | awk '{print $1}'
}

# Get file hash with intelligent caching
get_file_hash() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local current_mtime
  current_mtime=$(get_file_mtime "$file") || return 1

  # Check cache validity
  if [[ -n "${HASH_CACHE[$file]:-}" ]]; then
    local cached_mtime="${FILE_MTIME_CACHE[$file]:-}"
    if [[ "$cached_mtime" == "$current_mtime" ]]; then
      echo "${HASH_CACHE[$file]}"
      return 0
    fi
  fi

  # Calculate and cache new hash
  local hash
  hash=$(calculate_file_hash "$file") || return 1

  HASH_CACHE[$file]="$hash"
  FILE_MTIME_CACHE[$file]="$current_mtime"

  echo "$hash"
}

# Clear hash cache for forced recalculation
clear_hash_cache() {
  HASH_CACHE=()
  FILE_MTIME_CACHE=()
}

# Validate that a file exists and is readable
validate_file_exists() {
  local file="$1"
  local context="${2:-File}"

  if [[ ! -f "$file" ]]; then
    log_error "$context not found: $file"
    return 1
  fi

  if [[ ! -r "$file" ]]; then
    log_error "$context not readable: $file"
    return 1
  fi

  return 0
}

# Prompt user for confirmation with consistent formatting
prompt_confirmation() {
  local message="$1"
  local default="${2:-N}"
  local prompt_text

  if [[ "$default" =~ ^[Yy]$ ]]; then
    prompt_text="${message} (Y/n): "
  else
    prompt_text="${message} (y/N): "
  fi

  read -p "$prompt_text" response

  if [[ -z "$response" ]]; then
    [[ "$default" =~ ^[Yy]$ ]]
    return $?
  fi

  [[ "$response" =~ ^[Yy]$ ]]
}

# Validate that a command exists
validate_command() {
  local cmd="$1"
  local context="${2:-Command}"

  if ! command -v "$cmd" &>/dev/null; then
    log_error "$context not found: $cmd"
    log_error "Please install the required package providing this command"
    return 1
  fi
  return 0
}

# Cleanup function to restore backups on error
cleanup_on_error() {
  [[ "$CLEANUP_NEEDED" != "true" ]] && return 0

  log_warning "Attempting to restore from backups..."

  if [[ ${#BACKUP_FILES[@]} -gt 0 ]]; then
    local latest_backup="${BACKUP_FILES[-1]}"
    if [[ -f "$latest_backup" ]]; then
      if sudo cp "$latest_backup" "$LIMINE_CONF"; then
        log_success "Restored limine.conf from: $latest_backup"
      else
        log_error "Failed to restore limine.conf"
      fi
    fi
  fi

  CLEANUP_NEEDED=false
}

# Handle critical errors with cleanup and exit
handle_critical_error() {
  local error_msg="$1"
  local exit_code="${2:-1}"

  log_error "$error_msg"
  cleanup_on_error
  log_error "Operation failed. Check the error messages above for details."
  exit "$exit_code"
}

# ============================================================================
# SECTION 4: DISCOVERY FUNCTIONS
# ============================================================================

# Find all Linux-related EFI files dynamically
find_linux_efi_files() {
  local -a efi_files=()
  local file

  while IFS= read -r file; do
    [[ "$file" =~ [Mm]icrosoft|[Ww]indows|bootmgfw ]] && continue
    [[ -f "$file" ]] && [[ ! -d "$file" ]] && efi_files+=("$file")
  done < <(find /boot -type f -iname "*.efi" 2>/dev/null || true)

  printf '%s\n' "${efi_files[@]}"
}

# Find Windows Boot Manager across all mounted partitions
find_windows_bootmgr() {
  local bootmgr_path=""

  log_info "Searching for Windows Boot Manager..."

  local -a search_paths=(
    "/boot"
    "/boot/efi"
    "/efi"
    "/mnt/c"
    "/mnt/windows"
  )

  while IFS= read -r mount_point; do
    if [[ -n "$mount_point" ]] && [[ ! " ${search_paths[*]} " =~ " ${mount_point} " ]]; then
      search_paths+=("$mount_point")
    fi
  done < <(findmnt -t vfat,ntfs,ntfs3 -n -o TARGET 2>/dev/null || true)

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

  if [[ -z "$bootmgr_path" ]]; then
    local windows_parts
    windows_parts=$(lsblk -f -n -o NAME,FSTYPE,LABEL,MOUNTPOINT | grep -E "(ntfs|vfat)" | grep -v "/" | head -1 || true)
    [[ -n "$windows_parts" ]] && log_info "Found unmounted Windows partition(s). Consider mounting them to detect Windows."
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
    pacman -Qi "$package" >/dev/null 2>&1 || missing_packages+=("$package")
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    echo "${missing_packages[@]}"
    return 1
  fi
  return 0
}

# Check if secure boot keys exist
check_keys() {
  [[ -f /usr/share/secureboot/keys/db/db.key ]] && return 0
  [[ -f /var/lib/sbctl/keys/db/db.key ]] && return 0
  [[ -d /var/lib/sbctl/keys ]] && return 0
  sbctl status 2>/dev/null | grep -q "Installed:" && return 0
  return 1
}

# Check for hash mismatches in current kernel and snapshots
check_hash_mismatches() {
  local mismatches=0
  local total=0

  local machine_id
  machine_id=$(get_machine_id)
  [[ -z "$machine_id" ]] && {
    log_warning "Could not determine machine ID"
    return 0
  }

  local uki_file
  uki_file=$(find /boot -type f -name "${machine_id}_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)

  if [[ -f "$uki_file" ]]; then
    total=$((total + 1))
    local actual_hash
    if actual_hash=$(get_file_hash "$uki_file"); then
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
    else
      log_warning "Could not calculate hash for current kernel"
    fi
  fi

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
        if actual_hash=$(get_file_hash "$efi_path"); then
          local config_hash=""
          [[ "$line" =~ \#([a-f0-9]{128}) ]] && config_hash="${BASH_REMATCH[1]}"

          if [[ "$actual_hash" != "$config_hash" ]]; then
            mismatches=$((mismatches + 1))
            log_warning "Snapshot: hash mismatch - SHA256_${sha256_part:0:16}..."
            echo -e "  Config : ${config_hash:0:32}..."
            echo -e "  Actual : ${actual_hash:0:32}..."
          fi
        else
          log_warning "Could not calculate hash for snapshot: ${sha256_part:0:16}..."
        fi
      fi
    fi
  done < <(grep "limine_history" "$LIMINE_CONF" 2>/dev/null || true)

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

# Verify EFI file signatures
verify_signatures() {
  local quiet_mode="${1:-false}"
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)

  [[ ${#efi_files[@]} -eq 0 ]] && {
    log_warning "No EFI files found to verify"
    return 1
  }

  local all_verified=true
  local snapshot_count=0
  local current_count=0

  for file in "${efi_files[@]}"; do
    if [[ -f "$file" ]]; then
      local relpath
      relpath=$(get_relative_efi_path "$file")

      if [[ "$file" =~ limine_history ]]; then
        snapshot_count=$((snapshot_count + 1))
      elif [[ "$relpath" =~ _linux\.efi$ ]] && [[ ! "$file" =~ limine_history ]]; then
        current_count=$((current_count + 1))
      fi

      if ! timeout "$TIMEOUT_DURATION" sudo sbctl verify "$file" >/dev/null 2>&1; then
        all_verified=false
        [[ "$quiet_mode" != "true" ]] && echo "✗ $relpath"
      else
        [[ "$quiet_mode" != "true" ]] && echo "✓ $relpath"
      fi
    fi
  done

  [[ $snapshot_count -gt 0 ]] && [[ "$quiet_mode" != "true" ]] &&
    log_info "Verified $snapshot_count snapshot(s) and $current_count current kernel(s)"

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

  grep -q "NoExtract.*${noextract_entry}" "$PACMAN_CONF" 2>/dev/null &&
    {
      log_info "Pacman already configured to skip sbctl hook"
      return 0
    }

  log_info "Configuring pacman to prevent sbctl hook installation..."

  local backup_file="${PACMAN_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
  sudo cp "$PACMAN_CONF" "$backup_file" || {
    log_error "Failed to backup pacman.conf"
    return 1
  }
  log_info "Backup created: $backup_file"

  local has_noextract
  has_noextract=$(grep -n "^NoExtract" "$PACMAN_CONF" 2>/dev/null || echo "")

  if [[ -n "$has_noextract" ]]; then
    local line_num
    line_num=$(echo "$has_noextract" | head -1 | cut -d: -f1)

    if ! grep "^NoExtract" "$PACMAN_CONF" | grep -q "$noextract_entry"; then
      sudo sed -i "${line_num}s|$| ${noextract_entry}|" "$PACMAN_CONF" ||
        {
          log_error "Failed to update NoExtract line"
          return 1
        }
      log_success "Added sbctl hook to existing NoExtract configuration"
    fi
  else
    local options_line
    options_line=$(grep -n "^\[options\]" "$PACMAN_CONF" | head -1 | cut -d: -f1)

    if [[ -n "$options_line" ]]; then
      sudo sed -i "${options_line}a NoExtract = ${noextract_entry}" "$PACMAN_CONF" ||
        {
          log_error "Failed to add NoExtract configuration"
          return 1
        }
      log_success "Created NoExtract configuration for sbctl hook"
    else
      log_error "Could not find [options] section in pacman.conf"
      log_info "Please manually add to pacman.conf: NoExtract = ${noextract_entry}"
      return 1
    fi
  fi

  grep -q "NoExtract.*${noextract_entry}" "$PACMAN_CONF" &&
    {
      log_success "Pacman configuration updated successfully"
      return 0
    }

  log_error "Failed to update pacman configuration"
  return 1
}

# Remove NoExtract configuration
remove_pacman_noextract() {
  local noextract_entry="usr/share/libalpm/hooks/zz-sbctl.hook"

  grep -q "$noextract_entry" "$PACMAN_CONF" 2>/dev/null || return 0

  log_info "Removing NoExtract configuration..."

  sudo cp "$PACMAN_CONF" "${PACMAN_CONF}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null ||
    log_warning "Failed to backup pacman.conf before modification"

  sudo sed -i "s| *${noextract_entry}||g" "$PACMAN_CONF" ||
    {
      log_error "Failed to remove NoExtract entry"
      return 1
    }

  sudo sed -i '/^NoExtract[[:space:]]*=[[:space:]]*$/d' "$PACMAN_CONF" 2>/dev/null ||
    log_warning "Failed to remove empty NoExtract lines"

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
  sudo pacman -Syu --needed "${SB_PACKAGES[@]}" ||
    handle_critical_error "Failed to install required packages"

  check_packages >/dev/null || handle_critical_error "Package installation verification failed"
  log_success "Packages installed successfully"
}

# Install automation script and pacman hook
install_automation() {
  log_step "Installing Automation"

  validate_file_exists "$0" "Source script" ||
    handle_critical_error "Cannot install - source script not accessible"

  # Clean install
  [[ -f "$INSTALL_PATH" ]] && {
    log_info "Removing existing script..."
    sudo rm -f "$INSTALL_PATH"
  }

  for hook in "$HOOK_PATH" "$OLD_HOOK_PATH"; do
    [[ -f "$hook" ]] && {
      log_info "Removing existing hook: $(basename "$hook")"
      sudo rm -f "$hook"
    }
  done

  # Install script
  log_info "Installing script to $INSTALL_PATH"
  sudo cp "$0" "$INSTALL_PATH" || handle_critical_error "Failed to copy script to $INSTALL_PATH"
  sudo chmod +x "$INSTALL_PATH" || handle_critical_error "Failed to make script executable"

  # Create pacman hook
  log_info "Creating pacman hook at $HOOK_PATH"
  sudo tee "$HOOK_PATH" >/dev/null <<'HOOK_EOF' || handle_critical_error "Failed to create pacman hook"
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

  configure_pacman_noextract || {
    log_warning "Could not configure pacman.conf automatically"
    log_info "The sbctl hook may reappear after sbctl updates"
  }

  if [[ -f "$SBCTL_HOOK" ]]; then
    log_info "Removing incompatible sbctl hook..."
    sudo rm -f "$SBCTL_HOOK" && log_success "Removed sbctl hook - it won't return due to NoExtract" ||
      log_warning "Could not remove sbctl hook - may cause error messages"
  fi

  if [[ -f "$INSTALL_PATH" ]] && [[ -x "$INSTALL_PATH" ]] && [[ -f "$HOOK_PATH" ]]; then
    log_success "Automation installed successfully"
    log_info "System will now automatically maintain secure boot after package updates"
    grep -q "NoExtract.*zz-sbctl.hook" "$PACMAN_CONF" 2>/dev/null &&
      log_info "The problematic sbctl hook is permanently neutralized"
    return 0
  fi

  handle_critical_error "Installation verification failed"
}

# Create secure boot keys
create_keys() {
  log_step "Creating Secure Boot Keys"

  validate_command "sbctl" "sbctl command" ||
    handle_critical_error "sbctl not found - install required packages first"

  if check_keys; then
    log_warning "Secure boot keys already exist"
    timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || log_warning "Could not check sbctl status"
    echo ""
    prompt_confirmation "Recreate keys? This will invalidate existing signatures" ||
      {
        log_info "Keeping existing keys"
        return 0
      }
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
  cat <<EOF

${BOLD}${YELLOW}🔐 SECURE BOOT KEY ENROLLMENT REQUIRED${NC}
${YELLOW}=============================================${NC}
${YELLOW}Your secure boot keys have been created but need to be enrolled.${NC}

${CYAN}Next steps:${NC}
  ${BOLD}1.${NC} Reboot your system
  ${BOLD}2.${NC} Enter BIOS/UEFI setup (usually F2, F12, or Del during boot)
  ${BOLD}3.${NC} Navigate to Secure Boot settings
  ${BOLD}4.${NC} Clear/Delete all existing keys (enter Setup Mode)
  ${BOLD}5.${NC} Save changes and reboot back to Linux
  ${BOLD}6.${NC} Run: ${CYAN}$SCRIPT_NAME --enroll${NC}

${YELLOW}=============================================${NC}
EOF

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

  [[ ${#efi_files[@]} -eq 0 ]] && {
    log_warning "No Linux EFI files found to sign"
    return 1
  }

  validate_command "sbctl" "sbctl command" ||
    {
      log_error "Cannot sign files - sbctl not available"
      return 1
    }

  log_info "Found ${#efi_files[@]} Linux EFI files to process"

  local needs_signing=false
  for file in "${efi_files[@]}"; do
    [[ ! -f "$file" ]] || [[ -d "$file" ]] && continue

    local relpath
    relpath=$(get_relative_efi_path "$file")
    log_info "Checking $relpath"

    if sudo sbctl verify "$file" >/dev/null 2>&1; then
      echo "    ✓ already signed"
    else
      echo "    → signing..."
      if sudo sbctl sign -s "$file" >/dev/null 2>&1; then
        needs_signing=true
        unset HASH_CACHE[$file]
        unset FILE_MTIME_CACHE[$file]
      else
        log_warning "Failed to sign: $relpath"
      fi
    fi
  done

  [[ "$needs_signing" = true ]]
}

# Update hash for current UKI file
update_hash() {
  local machine_id
  machine_id=$(get_machine_id)
  [[ -z "$machine_id" ]] && {
    log_warning "Could not determine machine ID"
    return 1
  }

  local uki_file
  uki_file=$(find /boot -type f -name "${machine_id}_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)
  [[ -z "$uki_file" ]] && uki_file=$(find /boot -type f -name "*_linux.efi" 2>/dev/null | grep -v "limine_history" | head -1)

  validate_file_exists "$uki_file" "UKI file" || return 1
  validate_file_exists "$LIMINE_CONF" "Limine configuration" || return 1

  local new_hash current_hash
  new_hash=$(get_file_hash "$uki_file") || {
    log_error "Failed to calculate hash for UKI file"
    return 1
  }

  local uki_filename
  uki_filename=$(basename "$uki_file")

  if grep -qE "${uki_filename}" "$LIMINE_CONF"; then
    current_hash=$(grep -E "${uki_filename}" "$LIMINE_CONF" | grep -v "limine_history" |
      sed -E 's/.*#([0-9a-f]{128})/\1/' 2>/dev/null | head -1)
  fi

  if [[ "$new_hash" != "$current_hash" ]]; then
    log_info "Updating BLAKE2B hash for $uki_filename in limine.conf"
    CLEANUP_NEEDED=true
    sudo sed -i -E "s|(image_path:.*${uki_filename})(#.*)?$|\1#${new_hash}|" "$LIMINE_CONF" ||
      {
        log_error "Failed to update hash in limine.conf"
        return 1
      }
    CLEANUP_NEEDED=false
    log_success "Hash updated: ${new_hash:0:16}..."
    return 0
  fi

  return 1
}

# Process a single snapshot hash update
update_single_snapshot_hash() {
  local line_num="$1"
  local snapshot_filename="$2"
  local sha256_part="$3"

  local efi_path
  efi_path=$(find /boot -type f -path "*/limine_history/*_sha256_${sha256_part}" 2>/dev/null | head -1)

  validate_file_exists "$efi_path" "Snapshot EFI file" ||
    {
      log_warning "Snapshot file not found: SHA256 ${sha256_part:0:16}..."
      return 1
    }

  local new_hash
  new_hash=$(get_file_hash "$efi_path") ||
    {
      log_error "Failed to calculate hash for snapshot"
      return 1
    }

  local escaped_filename
  escaped_filename=$(echo "$snapshot_filename" | sed 's/[[\.*^$()+?{|]/\\&/g')

  if sudo sed -i "${line_num}s|\(image_path:.*${escaped_filename}\)\(#[a-f0-9]*\)\?|\1#${new_hash}|" "$LIMINE_CONF"; then
    log_success "Updated line $line_num: SHA256 ${sha256_part:0:16}..."
    return 0
  fi

  log_error "Failed to update line $line_num: SHA256 ${sha256_part:0:16}..."
  return 1
}

# Update snapshot UKI hashes after signing
update_snapshot_hashes() {
  log_step "Checking Snapshot UKI Hashes"

  validate_file_exists "$LIMINE_CONF" "Limine configuration" || return 1

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
        if actual_hash=$(get_file_hash "$efi_path"); then
          local config_hash=""
          [[ "$line_content" =~ \#([a-f0-9]{128}) ]] && config_hash="${BASH_REMATCH[1]}"

          if [[ "$actual_hash" != "$config_hash" ]]; then
            needs_update=$((needs_update + 1))
            updates_needed+=("${line_num}:${snapshot_filename}:${sha256_part}")
            log_detail "Line $line_num - SHA256_${sha256_part:0:16}...: hash mismatch"
            echo -e "    Config : ${config_hash:0:16}..."
            echo -e "    Actual : ${actual_hash:0:16}..."
          fi
        else
          log_warning "Could not calculate hash for snapshot: ${sha256_part:0:16}..."
        fi
      else
        log_warning "Snapshot file not found: SHA256 ${sha256_part:0:16}..."
      fi
    fi
  done < <(grep -n "limine_history/" "$LIMINE_CONF" 2>/dev/null || true)

  [[ $needs_update -eq 0 ]] && {
    log_success "All $checked snapshot hashes are already correct"
    return 0
  }

  echo ""
  log_warning "Found $needs_update snapshot(s) with incorrect hashes out of $checked checked"

  if [[ "$CONFIRM_BULK_CHANGES" == "true" ]]; then
    prompt_confirmation "Update snapshot hashes in limine.conf?" ||
      {
        log_info "Skipped snapshot hash updates"
        return 0
      }
  fi

  backup_limine_conf
  CLEANUP_NEEDED=true

  log_info "Updating snapshot hashes..."

  for update_entry in "${updates_needed[@]}"; do
    IFS=: read -r line_num snapshot_filename sha256_part <<<"$update_entry"
    update_single_snapshot_hash "$line_num" "$snapshot_filename" "$sha256_part" && updated=$((updated + 1))
  done

  CLEANUP_NEEDED=false

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

  lsblk -o LABEL 2>/dev/null | grep -qi "windows.*11\|win.*11" && windows_version="Microsoft Windows 11"
  lsblk -o LABEL 2>/dev/null | grep -qi "windows.*10\|win.*10" && windows_version="Microsoft Windows 10"
  find "$(dirname "$windows_path")" -name "*.mui" 2>/dev/null | grep -qi "windows.ui\|winui" &&
    windows_version="Microsoft Windows 11"

  echo "$windows_version"
}

# Check and add Windows entry to limine.conf
ensure_windows_entry() {
  log_step "Checking for Windows Boot Entry"

  validate_file_exists "$LIMINE_CONF" "Limine configuration" || return 1

  grep -qi "windows\|bootmgfw" "$LIMINE_CONF" 2>/dev/null &&
    {
      log_success "Windows entry already exists in limine.conf"
      return 0
    }

  local windows_path
  windows_path=$(find_windows_bootmgr)

  [[ -z "$windows_path" ]] && {
    log_info "No Windows installation detected"
    return 0
  }

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

  if prompt_confirmation "Add Windows entry to boot menu?"; then
    backup_limine_conf
    CLEANUP_NEEDED=true
    if echo "$windows_entry" | sudo tee -a "$LIMINE_CONF" >/dev/null; then
      CLEANUP_NEEDED=false
      log_success "Windows entry added to limine.conf"
    else
      log_error "Failed to add Windows entry"
      return 1
    fi
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

  [[ $EUID -eq 0 ]] && {
    log_error "Don't run setup as root. The script will use sudo when needed."
    exit 1
  }

  require_auth

  install_packages
  install_automation
  create_keys

  log_step "Initial EFI File Signing"
  sign_files && update_hash

  log_step "Checking for Hash Mismatches"
  check_hash_mismatches || log_info "Run '$SCRIPT_NAME --fix-hashes' to correct mismatches"

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

  check_keys || {
    log_error "No secure boot keys found"
    log_info "Create keys first: $SCRIPT_NAME --setup"
    log_info "Or manually: sudo sbctl create-keys"
    exit 1
  }

  validate_command "sbctl" "sbctl command" ||
    handle_critical_error "sbctl not found - install required packages first"

  local sb_status
  sb_status=$(timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || echo "")

  if echo "$sb_status" | grep -q "Setup Mode.*✓ Enabled\|Setup Mode.*Enabled"; then
    log_info "System is in Setup Mode - ready for enrollment"
  elif echo "$sb_status" | grep -q "Setup Mode.*✓ Disabled\|Setup Mode.*Disabled"; then
    log_warning "Keys appear to be already enrolled (Setup Mode is disabled)"
    log_info "Your secure boot setup may already be complete"
    echo ""
    prompt_confirmation "Continue with key enrollment anyway?" ||
      {
        log_info "Key enrollment cancelled"
        return 0
      }
  else
    log_warning "Cannot determine Setup Mode status"
    echo ""
    echo "To enter Setup Mode:"
    echo "  1. Reboot and enter BIOS/UEFI setup"
    echo "  2. Find Secure Boot settings"
    echo "  3. Clear/Delete all existing keys"
    echo "  4. Save and reboot"
    echo ""
    prompt_confirmation "Continue with key enrollment anyway?" ||
      {
        log_info "Key enrollment cancelled"
        return 0
      }
  fi

  log_info "Enrolling secure boot keys..."
  if sudo sbctl enroll-keys -m -f; then
    log_success "Keys enrolled successfully"
    timeout "$TIMEOUT_DURATION" sudo sbctl status 2>/dev/null || log_warning "Could not verify enrollment status"

    cat <<EOF

${BOLD}${GREEN}🔐 FINAL STEP: Enable Secure Boot${NC}
${GREEN}=================================${NC}
  ${BOLD}1.${NC} Reboot your system
  ${BOLD}2.${NC} Enter BIOS/UEFI setup
  ${BOLD}3.${NC} Enable Secure Boot
  ${BOLD}4.${NC} Save and reboot

${GREEN}After that, automatic maintenance will handle everything!${NC}
EOF
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

  [[ -z "$machine_id" ]] && {
    log_error "Could not determine machine ID"
    exit 1
  }

  log_info "Starting secure boot maintenance..."

  if [[ -t 0 ]]; then
    sudo -v 2>/dev/null || {
      log_error "Failed to authenticate"
      exit 1
    }
  fi

  local hash_updated=false
  local verification_passed=false

  sign_files || true
  update_hash && hash_updated=true
  verify_signatures "true" && verification_passed=true

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
  clear_hash_cache

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
  clear_hash_cache

  local current_fixed=false
  update_hash && {
    log_success "Fixed current kernel hash"
    current_fixed=true
  }

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

  check_keys && log_success "Secure boot keys exist" || log_warning "No secure boot keys found"

  if [[ -f "$INSTALL_PATH" ]] && [[ -f "$HOOK_PATH" ]]; then
    log_success "Automation installed and active"
  else
    log_warning "Automation not installed"
    [[ ! -f "$INSTALL_PATH" ]] && echo "  Missing: $INSTALL_PATH"
    [[ ! -f "$HOOK_PATH" ]] && echo "  Missing: $HOOK_PATH"
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
    [[ -n "$windows_path" ]] && log_warning "Windows detected but not in boot menu (run --add-windows to add)"
  fi

  echo ""
  log_info "Linux EFI files found:"
  local -a efi_files
  mapfile -t efi_files < <(find_linux_efi_files)
  local snapshot_count=0
  for file in "${efi_files[@]}"; do
    local relpath
    relpath=$(get_relative_efi_path "$file")
    echo "  - $relpath"
    [[ "$file" =~ limine_history ]] && snapshot_count=$((snapshot_count + 1))
  done
  [[ $snapshot_count -gt 0 ]] && log_info "Including $snapshot_count snapshot UKI(s)"

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

  cat <<EOF
This will remove:
  - The automation script from $INSTALL_PATH
  - The pacman hook from $HOOK_PATH
  - NoExtract configuration from pacman.conf

This will NOT remove:
  - Your secure boot keys
  - Any EFI signatures
  - Limine configuration changes

EOF

  prompt_confirmation "Continue with uninstall?" || {
    log_info "Uninstall cancelled"
    return 0
  }

  require_auth

  local removed_items=0

  if [[ -f "$INSTALL_PATH" ]]; then
    sudo rm -f "$INSTALL_PATH" && {
      log_success "Removed script"
      removed_items=$((removed_items + 1))
    } ||
      log_error "Failed to remove script"
  else
    log_info "Script not found (already removed?)"
  fi

  for hook in "$HOOK_PATH" "$OLD_HOOK_PATH"; do
    if [[ -f "$hook" ]]; then
      sudo rm -f "$hook" && {
        log_success "Removed hook: $(basename "$hook")"
        removed_items=$((removed_items + 1))
      } ||
        log_error "Failed to remove hook: $(basename "$hook")"
    fi
  done

  if grep -q "NoExtract.*zz-sbctl.hook" "$PACMAN_CONF" 2>/dev/null; then
    remove_pacman_noextract && removed_items=$((removed_items + 1))
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
  cat <<EOF
${BOLD}Omarchy Secure Boot Manager v${VERSION}${NC}
Complete setup and maintenance for Limine + UKI secure boot with snapshot support

${BOLD}USAGE:${NC}
  $0 [COMMAND]

${BOLD}SETUP COMMANDS:${NC}
  --setup        Complete setup for new systems
  --enroll       Enroll keys after BIOS setup
  --add-windows  Add Windows entry to boot menu

${BOLD}MAINTENANCE COMMANDS:${NC}
  --update       Update signatures and hashes (used by pacman hook)
  --sign         Manual signing of all EFI files
  --fix-hashes   Fix all hash mismatches (current + snapshots)
  --status       Show secure boot status and verification

${BOLD}MANAGEMENT:${NC}
  --uninstall    Remove automation (keeps keys and signatures)
  --help         Show this help message

${BOLD}TYPICAL WORKFLOW:${NC}
  1. $0 --setup
  2. Reboot → BIOS → Clear keys → Setup Mode → Reboot
  3. $0 --enroll
  4. Reboot → BIOS → Enable Secure Boot

${BOLD}v${VERSION} NEW FEATURES:${NC}
  • Hash caching for 3-5x faster operations
  • Improved error handling with automatic recovery
  • Reusable utility functions for cleaner code
  • Neutralizes conflicting sbctl hook permanently

EOF
}

# Main function - command dispatcher
main() {
  case "${1:-}" in
  --setup) cmd_setup ;;
  --enroll) cmd_enroll ;;
  --update) cmd_update ;;
  --sign) cmd_sign ;;
  --fix-hashes) cmd_fix_hashes ;;
  --status) cmd_status ;;
  --add-windows) cmd_add_windows ;;
  --uninstall) cmd_uninstall ;;
  --help | -h | "") show_usage ;;
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
