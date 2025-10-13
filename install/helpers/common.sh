#!/bin/bash
#
# Common helper functions used across Omarchy installation scripts
#

# clear_pipe_buffer - Drain any buffered input from stdin and /dev/tty
#
# Uses dd with non-blocking read to instantly consume all available input
# without iterating or blocking. This prevents accumulated yes_finite output
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
# 2. Generate exactly 100 "1" selections and pipe to command
# 3. Clear buffer after command completes (cleanup any leftovers)
#
# Typical package installs need 0-3 provider selections, but some of the
# commands install dozens of packages at the same time, so 100 should
# hopefully be enough to cover all cases without causing EPIPE errors.
# This prevents buffer accumulation that causes auto-confirmation issues.
#
# Usage: with_yes sudo pacman -S package
#        with_yes yay -S package
#        with_yes omarchy-aur-install package
#
with_yes() {
  clear_pipe_buffer  # Start with clean buffer
  printf '1\n%.0s' {1..100} | "$@"  # Execute command with 100 "1" responses
  local exit_code=$?
  clear_pipe_buffer  # Clean up any leftovers
  return $exit_code
}
