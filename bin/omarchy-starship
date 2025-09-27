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
        if [[ -z "$_STARSHIP_TRANSIENT_SETUP" ]]; then
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

function switch_starship_preset() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: spreset <preset_name>" >&2
        _list_presets
        return 1
    fi

    if [[ "$name" =~ [^a-zA-Z0-9_-] ]] || [[ "$name" == *"/"* ]] || [[ "$name" == *".."* ]]; then
        echo "Error: Invalid preset name. Only alphanumeric characters, hyphens, and underscores are allowed." >&2
        return 1
    fi

    local path="$STARSHIP_PRESETS_DIR/$name.toml"

    if [ ! -f "$path" ]; then
        echo "Error: No such preset: $name" >&2
        _list_presets
        return 1
    fi

    if ! echo "$name" > "$STARSHIP_STATE_FILE" 2>/dev/null; then
        echo "Error: Failed to save preset state" >&2
        return 1
    fi

    export STARSHIP_CONFIG="$path"

    case "$CURRENT_SHELL" in
        "zsh")
            echo "Preset switched to: $name"
            # Re-initialize starship with new config instead of full shell restart
            if command -v starship >/dev/null 2>&1; then
                eval "$(starship init zsh)"
                # Re-setup transient prompt if it was enabled
                if typeset -f starship_transient_prompt_setup >/dev/null 2>&1; then
                    starship_transient_prompt_setup
                fi
            fi
            ;;
        "bash")
            echo "Preset switched to: $name"
            # Re-initialize starship with new config
            if command -v starship >/dev/null 2>&1; then
                eval "$(starship init bash)"
            fi
            ;;
        *)
            echo "Preset switched to: $name"
            echo "Please restart your shell or re-source your config to apply changes"
            ;;
    esac
}


alias spreset='switch_starship_preset'
