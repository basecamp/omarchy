#!/usr/bin/env bash
set -euo pipefail

# Omarchy Secure Boot Updater
# Automatically manages signatures and hashes for Limine + UKI secure boot setup

# Configuration paths
readonly UKI_PATHS=("/boot/EFI/Linux" "/boot/EFI/linux")
readonly LIMINE_CONF="/boot/limine.conf"
readonly MACHINE_ID_FILE="/etc/machine-id"

# Static EFI files that need signing
readonly -a STATIC_EFI_FILES=(
  "/boot/EFI/BOOT/BOOTX64.EFI"
  "/boot/EFI/limine/BOOTX64.EFI"
  "/boot/EFI/limine/BOOTIA32.EFI"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Get machine ID with fallbacks
get_machine_id() {
  if [[ -f "$MACHINE_ID_FILE" ]]; then
    cat "$MACHINE_ID_FILE" | tr -d '\n'
  elif command -v systemd-machine-id-setup >/dev/null 2>&1; then
    systemd-machine-id-setup --print 2>/dev/null || echo ""
  else
    printf "%08x" "$(hostid)" 2>/dev/null || echo ""
  fi
}

# Find the correct UKI base path
get_uki_base() {
  local path
  for path in "${UKI_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
      echo "$path"
      return 0
    fi
  done
  # Default to first path if none exist
  echo "${UKI_PATHS[0]}"
}

# Get UKI file path
get_uki_file() {
  local machine_id="$1"
  local uki_base="$2"
  local uki_file="${uki_base}/${machine_id}_linux.efi"

  # If machine-specific doesn't exist, try to find any UKI
  if [[ ! -f "$uki_file" ]]; then
    uki_file=$(find "$uki_base" -name "*_linux.efi" 2>/dev/null | head -1)
  fi

  echo "$uki_file"
}

# Main execution
main() {
  echo -e "${BLUE}[omarchy-secureboot]${NC} Starting update"

  # Get machine ID and paths
  local machine_id
  machine_id=$(get_machine_id)

  if [[ -z "$machine_id" ]]; then
    echo -e "${RED}[ERROR]${NC} Could not determine machine ID"
    exit 1
  fi

  local uki_base
  uki_base=$(get_uki_base)

  local uki_file
  uki_file=$(get_uki_file "$machine_id" "$uki_base")

  # Start with static EFI files
  local -a efi_files=()
  local file
  for file in "${STATIC_EFI_FILES[@]}"; do
    efi_files+=("$file")
  done

  # Add main UKI file if it exists
  if [[ -n "$uki_file" ]]; then
    efi_files+=("$uki_file")
    echo -e " ${BLUE}→${NC} Including UKI file: $(basename "$uki_file")"
  fi

  # Add UKI if it exists
  if [[ -n "$uki_file" ]]; then
    efi_files+=("$uki_file")
  fi

  # Sign files that need signing
  local file
  local needs_signing=false

  for file in "${efi_files[@]}"; do
    if [[ -f "$file" ]]; then
      echo -e " ${BLUE}→${NC} checking $(basename "$file")"
      if sbctl verify "$file" >/dev/null 2>&1; then
        echo -e "    ${GREEN}[ok]${NC} already signed"
      else
        echo -e "    ${YELLOW}[!]${NC} not signed / invalid, signing now"
        sbctl sign -s "$file"
        needs_signing=true
      fi
    else
      echo -e "    ${YELLOW}[skipped]${NC} not present: $(basename "$file")"
    fi
  done

  # Update UKI hash if needed
  if [[ -f "$uki_file" && -f "$LIMINE_CONF" ]]; then
    local new_hash
    new_hash=$(b2sum "$uki_file" | awk '{print $1}')

    local current_hash=""
    if grep -qE "${machine_id}_linux\.efi" "$LIMINE_CONF"; then
      current_hash=$(grep -E "${machine_id}_linux\.efi" "$LIMINE_CONF" |
        sed -E 's/.*#([0-9a-f]{128})/\1/' 2>/dev/null || true)
    fi

    if [[ "$new_hash" != "$current_hash" ]]; then
      echo -e " ${BLUE}→${NC} updating limine.conf with new BLAKE2B hash ${new_hash:0:16}..."

      # Update hash in config (no backup created)
      sed -i -E "s|(image_path:.*${machine_id}_linux\.efi)(#.*)?$|\1#${new_hash}|" \
        "$LIMINE_CONF"

      echo -e "    ${GREEN}[ok]${NC} BLAKE2B hash updated successfully"
    else
      echo -e " ${BLUE}→${NC} BLAKE2B hash already up to date"
    fi
  elif [[ ! -f "$uki_file" ]]; then
    echo -e " ${YELLOW}→${NC} UKI not found: $(basename "$uki_file"), skipping hash update"
  elif [[ ! -f "$LIMINE_CONF" ]]; then
    echo -e " ${YELLOW}→${NC} limine.conf not found, skipping hash update"
  fi

  # Final verification
  if [[ "$needs_signing" == true ]]; then
    echo -e " ${BLUE}→${NC} verifying all signed files"
    if sbctl verify >/dev/null 2>&1; then
      echo -e "    ${GREEN}[ok]${NC} all files verified successfully"
    else
      echo -e "    ${YELLOW}[warning]${NC} some files may still have issues"
      sbctl verify || true
    fi
  fi

  echo -e "${GREEN}[omarchy-secureboot]${NC} Update complete"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
