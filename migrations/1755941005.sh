#!/bin/bash

set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
THEME_DIR="$HOME/.config/omarchy/themes"
INIT_FILE="$HOME/.config/nvim/lua/omarchy/init.lua"

# Counters
TOTAL_THEMES=0
SUCCESSFUL_MIGRATIONS=0
FAILED_MIGRATIONS=0

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    if [[ ! -d "$THEME_DIR" ]]; then
        error "Theme directory not found: $THEME_DIR"
        return 1
    fi
    
    if [[ ! -f "$INIT_FILE" ]]; then
        error "Omarchy init.lua not found: $INIT_FILE"
        return 1
    fi
    
    success "Prerequisites check passed"
    return 0
}

# Extract plugin repository from neovim.lua
extract_plugin_repo() {
    local neovim_file="$1"
    grep -Eo '"[^"/]+/[^"]+"' "$neovim_file" | grep -v "LazyVim/LazyVim" | head -n1 | tr -d '"' || echo ""
}

# Extract colorscheme from neovim.lua
extract_colorscheme() {
    local neovim_file="$1"
    local colorscheme
    colorscheme=$(grep -Eo 'colorscheme[[:space:]]*=[[:space:]]*"[^"]+"' "$neovim_file" | sed -E 's/.*"([^"]+)".*/\1/' | tail -n1 || echo "")
    
    if [[ -z "$colorscheme" ]]; then
        # Fallback: use repo name without .nvim suffix
        local plugin_repo
        plugin_repo=$(extract_plugin_repo "$neovim_file")
        if [[ -n "$plugin_repo" ]]; then
            colorscheme=${plugin_repo##*/}
            colorscheme=${colorscheme%.nvim}
        fi
    fi
    
    echo "$colorscheme"
}

# Add plugin to init.lua if not present
add_plugin() {
    local plugin_repo="$1"
    local plugin_entry="{ \"$plugin_repo\", lazy = false }"
    
    # Check if plugin already exists
    if grep -qF -- "$plugin_repo" "$INIT_FILE"; then
        return 0
    fi
    
    # Add plugin under -- Themes section
    local tmpfile
    if ! tmpfile=$(mktemp 2>/dev/null); then
        error "Failed to create temporary file for plugin: $plugin_repo"
        return 1
    fi
    
    if ! awk -v pe="$plugin_entry" '
        BEGIN { inserted=0; in_plugins=0 }
        /plugins[[:space:]]*=[[:space:]]*\{/ { in_plugins=1 }
        {
            if (!inserted && $0 ~ /--[[:space:]]*Themes/) {
                print $0
                print "    " pe ","
                inserted=1
                next
            }
            if (!inserted && in_plugins && $0 ~ /^[[:space:]]*},[[:space:]]*$/) {
                print "    " pe ","
                print $0
                inserted=1
                in_plugins=0
                next
            }
            print $0
        }
    ' "$INIT_FILE" > "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile" 2>/dev/null || true
        error "Failed to process init.lua for plugin: $plugin_repo"
        return 1
    fi
    
    if mv "$tmpfile" "$INIT_FILE" 2>/dev/null; then
        info "Added plugin: $plugin_repo"
        return 0
    else
        rm -f "$tmpfile" 2>/dev/null || true
        error "Failed to add plugin: $plugin_repo"
        return 1
    fi
}

# Add colorscheme to init.lua if not present
add_colorscheme() {
    local colorscheme="$1"
    
    # Check if colorscheme already exists
    if grep -q "\"${colorscheme}\"" "$INIT_FILE"; then
        return 0
    fi
    
    # Add colorscheme to install.colorscheme array
    local tmpfile
    if ! tmpfile=$(mktemp 2>/dev/null); then
        error "Failed to create temporary file for colorscheme: $colorscheme"
        return 1
    fi
    
    if ! awk -v cs="$colorscheme" '
        BEGIN { in_colors=0; in_install=0 }
        /install[[:space:]]*=[[:space:]]*\{/ { in_install=1 }
        in_install && /colorscheme[[:space:]]*=[[:space:]]*\{/ { in_colors=1 }
        {
            if (in_colors && $0 ~ /\}/) {
                print "      \"" cs "\","
                print $0
                in_colors=0; in_install=0
                next
            }
            print $0
        }
    ' "$INIT_FILE" > "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile" 2>/dev/null || true
        error "Failed to process init.lua for colorscheme: $colorscheme"
        return 1
    fi
    
    if mv "$tmpfile" "$INIT_FILE" 2>/dev/null; then
        info "Added colorscheme: $colorscheme"
        return 0
    else
        rm -f "$tmpfile" 2>/dev/null || true
        error "Failed to add colorscheme: $colorscheme"
        return 1
    fi
}

# Migrate a single theme
migrate_theme() {
    local theme_path="$1"
    local theme_name=$(basename "$theme_path")
    local neovim_file="$theme_path/neovim.lua"
    
    info "Processing theme: $theme_name"
    
    # Check if neovim.lua exists
    if [[ ! -f "$neovim_file" ]]; then
        warn "No neovim.lua found in $theme_name, skipping"
        return 1
    fi
    
    # Extract plugin and colorscheme
    local plugin_repo colorscheme
    plugin_repo=$(extract_plugin_repo "$neovim_file")
    colorscheme=$(extract_colorscheme "$neovim_file")
    
    if [[ -z "$plugin_repo" ]]; then
        warn "No plugin repository found in $theme_name, skipping"
        return 1
    fi
    
    if [[ -z "$colorscheme" ]]; then
        warn "No colorscheme found in $theme_name, skipping"
        return 1
    fi
    
    info "  Plugin: $plugin_repo"
    info "  Colorscheme: $colorscheme"
    
    # Add plugin and colorscheme
    local success=true
    if ! add_plugin "$plugin_repo"; then
        success=false
    fi
    
    if ! add_colorscheme "$colorscheme"; then
        success=false
    fi
    
    if [[ "$success" == true ]]; then
        success "Migrated theme: $theme_name"
        ((SUCCESSFUL_MIGRATIONS++))
        return 0
    else
        error "Failed to migrate theme: $theme_name"
        ((FAILED_MIGRATIONS++))
        return 1
    fi
}

process_themes() {
    info "Scanning for themes in: $THEME_DIR"
    
    # Find all theme directories with neovim.lua files - handle errors gracefully
    local theme_paths=()
    if [[ -d "$THEME_DIR" ]]; then
        while IFS= read -r -d '' neovim_file; do
            local theme_dir=$(dirname "$neovim_file")
            local theme_name=$(basename "$theme_dir")
            
            # Skip hidden directories
            if [[ "$theme_name" =~ ^\. ]]; then
                continue
            fi
            
            theme_paths+=("$theme_dir")
        done < <(find "$THEME_DIR" -name "neovim.lua" -type f -print0 2>/dev/null || true)
    fi
    
    TOTAL_THEMES=${#theme_paths[@]}
    
    if [[ $TOTAL_THEMES -eq 0 ]]; then
        warn "No themes with neovim.lua files found"
        return 0  # Return success for graceful failure
    fi
    
    info "Found $TOTAL_THEMES theme(s) to process"
    echo ""
    
    # Process each theme - continue even if individual themes fail
    for theme_path in "${theme_paths[@]}"; do
        migrate_theme "$theme_path" || true
        echo ""
    done
    
    return 0
}

# Generate summary report
generate_report() {
    echo "========================================"
    echo "         MIGRATION SUMMARY"
    echo "========================================"
    echo ""
    echo "Theme Directory: $THEME_DIR"
    echo "Total Themes: $TOTAL_THEMES"
    echo "Successful: $SUCCESSFUL_MIGRATIONS"
    echo "Failed: $FAILED_MIGRATIONS"
    echo ""
    
    if [[ $TOTAL_THEMES -eq 0 ]]; then
        warn "No themes found to migrate"
    elif [[ $FAILED_MIGRATIONS -gt 0 ]]; then
        warn "Migration completed with $FAILED_MIGRATIONS failed theme(s)"
        warn "This is non-fatal - other migrations can continue"
    else
        success "Migration completed successfully - all $SUCCESSFUL_MIGRATIONS theme(s) migrated"
    fi
    
    # Always return success for graceful failure
    return 0
}

# Main function
main() {
    echo "Omarchy Theme Migration"
    echo "======================"
    echo ""
    
    # Check prerequisites - continue even if they fail
    if ! check_prerequisites; then
        warn "Prerequisites check failed - migration may not work properly"
        warn "Continuing anyway..."
        echo ""
    fi
    
    process_themes
    echo ""
    
    generate_report
    
    # exit successfully so other migration scripts can continue
    exit 0
}

# Run migration
main