#!/bin/bash

# LG TV Management Setup
# Installs and configures LG TV power management tools

if [ "$ADD_LG_TV_SUPPORT" = "y" ]; then
  echo "Setting up LG TV management..."
  
  # Install Python using mise
  echo "Installing Python with mise..."
  mise use --global python@latest
  
  # Install bscpylgtv using mise
  echo "Installing bscpylgtv..."
  mise exec python -- python -m pip install bscpylgtv
  
else
  echo "LG TV management skipped (not requested in Q&A)"
fi