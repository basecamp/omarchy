#!/bin/bash

# Walker - Application launcher for ARM
# Always builds from AUR source to stay compatible with system GTK4/glib2

if command -v walker &>/dev/null; then
  echo "walker already installed, skipping"
  return 0
fi

echo "Building walker from source for ARM..."
"$OMARCHY_PATH/bin/omarchy-aur-install" walker
