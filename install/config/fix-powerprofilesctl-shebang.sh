# Ensure we use system python3 and not mise's python3
sudo sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
