#!/bin/bash
#
# Common helper functions used across Omarchy installation scripts
#

# yes_finite - Drop-in replacement for 'yes 1' that avoids EPIPE errors
#
# Problem: Using 'yes 1 | command' creates an infinite stream that keeps
# writing even after the command closes stdin, causing EPIPE errors.
# This is especially problematic with verbose build processes (signal-desktop, etc.)
#
# Solution: Generate exactly 100 "1" selections then exit cleanly.
# This is more than enough for any provider selection prompts.
#
# Usage: yes_finite | sudo pacman -S package
#        yes_finite | yay -S package
#
yes_finite() {
  printf '1\n%.0s' {1..100}
}
