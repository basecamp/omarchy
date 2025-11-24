echo "Installing Pinta for ARM..."

# Check if Pinta is already installed
if command -v pinta &>/dev/null; then
  echo "Pinta already installed, skipping"
  return 0
fi

# Install .NET 10 SDK and runtime from dotnet-core-10.0-bin split package
# Note: Using .NET 10 instead of .NET 8 because dotnet-core-8.0-bin
# has a broken dependency on non-existent 'netstandard-targeting-pack' package
# The 10.0 packages provide unversioned 'dotnet-runtime' that pinta-git requires
# (the 8.0 packages only provide 'dotnet-runtime-8.0' which doesn't satisfy the dep)
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" \
  dotnet-host-10.0-bin \
  dotnet-runtime-10.0-bin \
  dotnet-sdk-10.0-bin

# Now install Pinta - its deps will be satisfied by the above packages
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" pinta-git

echo "Pinta installed successfully"
