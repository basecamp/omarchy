echo "Installing Pinta for ARM..."

# Check if Pinta is already installed
if command -v pinta &>/dev/null; then
  echo "Pinta already installed, skipping"
  return 0
fi

# Install .NET host first (required by runtime packages)
# dotnet-host-bin is from dotnet-core-bin split package (separate from 8.0 packages)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" dotnet-host-bin

# Install specific .NET 8.0 dependencies
# .NET 8 is the current LTS version - using specific versioned packages
# These are part of dotnet-core-8.0-bin split package (now in KNOWN_SPLIT_PACKAGES)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" \
  dotnet-sdk-8.0-bin \
  dotnet-runtime-8.0-bin

# Now install Pinta - its deps will be satisfied by the above packages
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" pinta-git

echo "Pinta installed successfully"
