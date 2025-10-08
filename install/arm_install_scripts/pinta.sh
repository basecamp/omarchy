echo "Installing Pinta for ARM..."

# Check if Pinta is already installed
if command -v pinta &>/dev/null; then
  echo "Pinta already installed, skipping"
  return 0
fi

# Install specific .NET dependencies first to avoid interactive prompts
# .NET 8 is the current LTS version
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" \
  dotnet-sdk-8.0-bin \
  dotnet-host-bin \
  dotnet-runtime-8.0-bin

# Now install Pinta
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" pinta-git

echo "Pinta installed successfully"
