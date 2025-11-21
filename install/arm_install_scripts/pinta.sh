echo "Installing Pinta for ARM..."

# Check if Pinta is already installed
if command -v pinta &>/dev/null; then
  echo "Pinta already installed, skipping"
  return 0
fi

# Install .NET SDK and runtime from the generic dotnet-core-bin package
# Note: Using .NET 10 (latest) instead of .NET 8 because dotnet-core-8.0-bin
# has a broken dependency on non-existent 'netstandard-targeting-pack' package
# The generic packages provide dotnet-sdk and dotnet-runtime virtual packages
# that pinta-git requires
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" \
  dotnet-host-bin \
  dotnet-runtime-bin \
  dotnet-sdk-bin

# Now install Pinta - its deps will be satisfied by the above packages
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" pinta-git

echo "Pinta installed successfully"
