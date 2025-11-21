echo "Installing tobi-try for ARM..."

# Check if try is already installed
if command -v try &>/dev/null; then
  echo "tobi-try already installed, skipping"
  return 0
fi

# Download try.rb from GitHub
echo "Downloading try.rb from GitHub..."
curl -fsSL "https://raw.githubusercontent.com/tobi/try/main/try.rb" -o /tmp/try.rb

# Fix shebang to use system Ruby (avoid mise conflicts)
sed -i '1s|.*|#!/usr/bin/ruby|' /tmp/try.rb

# Install to /usr/bin
sudo install -Dm755 /tmp/try.rb /usr/bin/try

# Cleanup
rm -f /tmp/try.rb

echo "tobi-try installed successfully"
