# Detect the current running shell, not the default shell
if [ -n "$ZSH_VERSION" ]; then
    CURRENT_SHELL="zsh"
elif [ -n "$BASH_VERSION" ]; then
    CURRENT_SHELL="bash"
else
    # Fallback to checking the process name (optimized parameter expansion)
    CURRENT_SHELL="${0##*/}"
    [ -z "$CURRENT_SHELL" ] && CURRENT_SHELL="unknown"
fi


export STARSHIP_PRESETS_DIR="${HOME}/.config/starship/presets"
STARSHIP_STATE_FILE="$STARSHIP_PRESETS_DIR/current_preset"

STARSHIP_SUCCESS_COLOR="${STARSHIP_SUCCESS_COLOR:-#a6e3a1}"  # Catppuccin Green
STARSHIP_ERROR_COLOR="${STARSHIP_ERROR_COLOR:-#f38ba8}"      # Catppuccin Red
STARSHIP_TRANSIENT_PROMPT="${STARSHIP_TRANSIENT_PROMPT:-true}"  # Enable/disable transient prompt

if [ "$CURRENT_SHELL" = "zsh" ]; then
    function _starship_transient_prompt() {
        local exit_code=$?
        local prompt_char
        if [[ $exit_code -eq 0 ]]; then
            prompt_char="%F{$STARSHIP_SUCCESS_COLOR}❯%f"
        else
            prompt_char="%F{$STARSHIP_ERROR_COLOR}❯%f"
        fi

        # Set minimal transient prompt with newline for spacing
        PROMPT="$prompt_char "
        RPROMPT=''
    }

    function _starship_restore_prompt() {
        eval "$(starship init zsh)"
    }

    # Hook: Replace prompt with transient version after command execution
    function _starship_zle_line_finish() {
        _starship_transient_prompt
        zle reset-prompt
    }

    # Hook: Restore full prompt when starting to type a new command
    function _starship_zle_line_init() {
        # Only restore if we're starting a new command line
        if [[ -z "$BUFFER" ]]; then
            _starship_restore_prompt
            zle reset-prompt
        fi
    }

    function starship_transient_prompt_setup() {
        # Only setup transient prompt if enabled
        if [[ "$STARSHIP_TRANSIENT_PROMPT" == "true" ]] && [[ -z "$_STARSHIP_TRANSIENT_SETUP" ]]; then
            # Register the ZLE widgets only if zle is available
            if [[ -n "$ZSH_VERSION" ]] && (($+widgets)); then
                zle -N zle-line-finish _starship_zle_line_finish
                zle -N zle-line-init _starship_zle_line_init
                export _STARSHIP_TRANSIENT_SETUP=1
            fi
        fi
    }
fi


case "$CURRENT_SHELL" in
    "zsh")
        eval "$(starship init zsh)"

        if command -v starship >/dev/null 2>&1; then
            # Set up the transient prompt in precmd hook to ensure proper timing
            autoload -Uz add-zsh-hook
            add-zsh-hook precmd starship_transient_prompt_setup
        fi
        ;;
    "bash")
        eval "$(starship init bash)"
        ;;
    *)
        if command -v starship >/dev/null 2>&1; then
            eval "$(starship init "$CURRENT_SHELL" 2>/dev/null || starship init bash)"
        fi
        ;;
esac


if [ ! -d "$STARSHIP_PRESETS_DIR" ]; then
    if ! mkdir -p "$STARSHIP_PRESETS_DIR" 2>/dev/null; then
        echo "Warning: Cannot create starship presets directory: $STARSHIP_PRESETS_DIR" >&2
        # Fallback to using default starship config
        unset STARSHIP_CONFIG
    fi
fi

# Load current preset configuration
if [ -f "$STARSHIP_STATE_FILE" ]; then
    if read -r current_preset < "$STARSHIP_STATE_FILE" 2>/dev/null && [ -n "$current_preset" ]; then
        preset_path="$STARSHIP_PRESETS_DIR/$current_preset.toml"
        if [ -f "$preset_path" ]; then
            export STARSHIP_CONFIG="$preset_path"
        else
            # Preset file missing, clean up and use default
            rm -f "$STARSHIP_STATE_FILE" 2>/dev/null
            export STARSHIP_CONFIG="$STARSHIP_PRESETS_DIR/starship.toml"
        fi
    else
        # State file corrupted, clean up
        rm -f "$STARSHIP_STATE_FILE" 2>/dev/null
        export STARSHIP_CONFIG="$STARSHIP_PRESETS_DIR/starship.toml"
    fi
else
    export STARSHIP_CONFIG="$STARSHIP_PRESETS_DIR/starship.toml"
fi

function _list_presets() {
    echo "Available presets:"
    if [ -d "$STARSHIP_PRESETS_DIR" ]; then
        local found_presets=false
        for preset in "$STARSHIP_PRESETS_DIR"/*.toml; do
            if [ -f "$preset" ]; then
                preset_name="${preset##*/}"
                preset_name="${preset_name%.toml}"
                echo "  $preset_name"
                found_presets=true
            fi
        done
        if [ "$found_presets" = false ]; then
            echo "  No presets found"
        fi
    else
        echo "  Presets directory not found: $STARSHIP_PRESETS_DIR"
    fi
}

# Check if a TOML file has palette support
function _has_palette_support() {
    local toml_file="$1"
    if [ ! -f "$toml_file" ]; then
        return 1
    fi
    grep -q '^palette[[:space:]]*=' "$toml_file" 2>/dev/null
}

# Extract available palettes from a TOML file
function _extract_palettes() {
    local toml_file="$1"
    if [ ! -f "$toml_file" ]; then
        return 1
    fi

    # Find all [palettes.palette_name] sections
    grep '^\[palettes\.' "$toml_file" 2>/dev/null | \
    sed 's/^\[palettes\.\([^]]*\)\].*/\1/' | \
    sort
}

# List palettes for a specific preset
function _list_preset_palettes() {
    local preset_name="$1"
    local toml_file="$STARSHIP_PRESETS_DIR/$preset_name.toml"

    if [ ! -f "$toml_file" ]; then
        echo "Error: Preset '$preset_name' not found" >&2
        return 1
    fi

    if ! _has_palette_support "$toml_file"; then
        echo "Error: Preset '$preset_name' doesn't support palette switching" >&2
        return 1
    fi

    echo "Available palettes for '$preset_name':"
    local palettes
    palettes=$(_extract_palettes "$toml_file")
    if [ -n "$palettes" ]; then
        echo "$palettes" | while read -r palette; do
            echo "  $palette"
        done
    else
        echo "  No palettes found"
    fi
}

# Change palette in a TOML file using sed (BSD/GNU compatible)
function _change_palette() {
    local toml_file="$1"
    local new_palette="$2"
    local temp_file

    if [ ! -f "$toml_file" ]; then
        echo "Error: File '$toml_file' not found" >&2
        return 1
    fi

    if ! _has_palette_support "$toml_file"; then
        echo "Error: File doesn't support palette switching" >&2
        return 1
    fi

    # Validate that the palette exists in the file
    if ! _extract_palettes "$toml_file" | grep -q "^$new_palette$"; then
        echo "Error: Palette '$new_palette' not found in preset" >&2
        echo "Available palettes:"
        _extract_palettes "$toml_file" | while read -r palette; do
            echo "  $palette"
        done
        return 1
    fi

    # Create a temporary file for BSD/GNU sed compatibility
    temp_file=$(mktemp "${toml_file}.tmp.XXXXXX") || {
        echo "Error: Cannot create temporary file" >&2
        return 1
    }

    # Use sed to replace the palette line (compatible with both BSD and GNU sed)
    if sed 's/^palette[[:space:]]*=.*$/palette = "'"$new_palette"'"/' "$toml_file" > "$temp_file"; then
        if mv "$temp_file" "$toml_file"; then
            echo "Palette changed to: $new_palette"
            return 0
        else
            echo "Error: Failed to update file" >&2
            rm -f "$temp_file" 2>/dev/null
            return 1
        fi
    else
        echo "Error: Failed to process file" >&2
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
}

# Show help for spreset command
function _show_spreset_help() {
    cat << 'EOF'
Usage: spreset <preset_name> [options]
       spreset --help

Switch between starship presets and manage palette themes.

Commands:
  spreset <preset>                    Switch to the specified preset
  spreset <preset> --palette=<name>   Switch preset and change palette (if supported)
  spreset <preset> --list-palettes    List available palettes for the preset
  spreset --help                      Show this help message

Examples:
  spreset catppuccin                                # Switch to catppuccin preset
  spreset catppuccin --palette=catppuccin_mocha     # Switch and set mocha palette
  spreset catppuccin --list-palettes                # List catppuccin palettes
  spreset starship                                  # Switch to starship preset
  spreset --help                                    # Show this help

Note: Palette switching only works with presets that support the palette system.
EOF
}

function switch_starship_preset() {
    local preset_name=""
    local palette_name=""
    local list_palettes=false
    local show_help=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --palette=*)
                palette_name="${1#--palette=}"
                shift
                ;;
            --list-palettes)
                list_palettes=true
                shift
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                echo "Use 'spreset --help' for usage information." >&2
                return 1
                ;;
            *)
                if [ -z "$preset_name" ]; then
                    preset_name="$1"
                else
                    echo "Error: Multiple preset names specified" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    # Handle help
    if [ "$show_help" = true ]; then
        _show_spreset_help
        return 0
    fi

    # Handle list-palettes
    if [ "$list_palettes" = true ]; then
        if [ -z "$preset_name" ]; then
            echo "Error: Preset name required for --list-palettes" >&2
            echo "Usage: spreset <preset_name> --list-palettes" >&2
            return 1
        fi
        _list_preset_palettes "$preset_name"
        return $?
    fi

    # Require preset name for other operations
    if [ -z "$preset_name" ]; then
        _show_spreset_help
        return 1
    fi

    # Validate preset name
    if [[ "$preset_name" =~ [^a-zA-Z0-9_-] ]] || [[ "$preset_name" == *"/"* ]] || [[ "$preset_name" == *".."* ]]; then
        echo "Error: Invalid preset name. Only alphanumeric characters, hyphens, and underscores are allowed." >&2
        return 1
    fi

    local preset_path="$STARSHIP_PRESETS_DIR/$preset_name.toml"

    # Check if preset exists
    if [ ! -f "$preset_path" ]; then
        echo "Error: No such preset: $preset_name" >&2
        _list_presets
        return 1
    fi

    # Handle palette change if specified
    if [ -n "$palette_name" ]; then
        if ! _change_palette "$preset_path" "$palette_name"; then
            return 1
        fi
    fi

    # Switch to the preset
    if ! echo "$preset_name" > "$STARSHIP_STATE_FILE" 2>/dev/null; then
        echo "Error: Failed to save preset state" >&2
        return 1
    fi

    export STARSHIP_CONFIG="$preset_path"

    case "$CURRENT_SHELL" in
        "zsh")
            echo "Preset switched to: $preset_name"
            # Re-initialize starship with new config instead of full shell restart
            if command -v starship >/dev/null 2>&1; then
                eval "$(starship init zsh)"
                # Reset and re-setup transient prompt if it's enabled
                if [[ "$STARSHIP_TRANSIENT_PROMPT" == "true" ]] && typeset -f starship_transient_prompt_setup >/dev/null 2>&1; then
                    # Reset the transient prompt setup flag to allow re-initialization
                    unset _STARSHIP_TRANSIENT_SETUP
                    starship_transient_prompt_setup
                fi
            fi
            ;;
        "bash")
            echo "Preset switched to: $preset_name"
            # Re-initialize starship with new config
            if command -v starship >/dev/null 2>&1; then
                eval "$(starship init bash)"
            fi
            ;;
        *)
            echo "Preset switched to: $preset_name"
            echo "Please restart your shell or re-source your config to apply changes"
            ;;
    esac
}


alias spreset='switch_starship_preset'
