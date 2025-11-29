#!/bin/bash
#
# Common helper functions used across Omarchy installation scripts
#

# clear_pipe_buffer - Drain any buffered input from stdin and /dev/tty
#
# Uses dd with non-blocking read to instantly consume all available input
# without iterating or blocking. This prevents accumulated with_yes output
# from causing auto-confirmation in later interactive prompts.
#
clear_pipe_buffer() {
  # Drain stdin using dd with non-blocking read (instant, no iteration)
  dd if=/dev/stdin iflag=nonblock of=/dev/null 2>/dev/null || true
  # Drain /dev/tty as well (in case output was redirected there)
  dd if=/dev/tty iflag=nonblock of=/dev/null 2>/dev/null || true
}

# with_yes - Execute a command with auto-confirmation, managing buffer cleanup
#
# Avoids EPIPE errors and buffer accumulation that causes auto-confirmation issues.
#
# Solution:
# 1. Clear any accumulated buffer before starting (start fresh)
# 2. Dynamically calculate number of "1" selections based on package count
# 3. Clear buffer after command completes (cleanup any leftovers)
#
# Calculates yes count by:
# - Counting arguments that aren't commands/flags (rough package count)
# - Generating 5 "yes" responses per package (most need 0-1, some need 2-3)
# - Enforcing minimum of 50 and maximum of 500 to handle edge cases
#
# Usage: with_yes sudo pacman -S package1 package2 ...
#        with_yes yay -S package1 package2 ...
#        with_yes omarchy-aur-install package1 package2 ...
#
with_yes() {
  # Count packages (rough estimation by excluding commands and flags)
  local pkg_count=0
  for arg in "$@"; do
    case "$arg" in
      # Skip common commands and any flags
      sudo|pacman|yay|omarchy-aur-install|-*|--*)
        continue ;;
      # Count everything else as a package
      *)
        pkg_count=$((pkg_count + 1)) ;;
    esac
  done

  # Generate 5 yeses per package (min 50, max 500)
  local yes_count=$((pkg_count * 5))
  yes_count=$((yes_count < 50 ? 50 : yes_count))
  yes_count=$((yes_count > 500 ? 500 : yes_count))

  clear_pipe_buffer  # Start with clean buffer
  printf '1\n%.0s' $(seq 1 $yes_count) | "$@"  # Execute passed in commands w/ calculated 1\n ("yes") responses
  local exit_code=$?
  clear_pipe_buffer  # Clean up any leftovers
  return $exit_code
}
