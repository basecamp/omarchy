# Ensure we use system python3 and not mise's python3
# Only fix if the file exists (may not be installed on all systems)
if [[ -f /usr/bin/powerprofilesctl ]]; then
  sudo sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
fi
