echo "Installing tobi-try for ARM..."

# Check if try is already installed
if command -v try &>/dev/null; then
  echo "tobi-try already installed, skipping"
  return 0
fi

# Download try.rb and lib files from GitHub
echo "Downloading tobi-try from GitHub..."
curl -fsSL "https://raw.githubusercontent.com/tobi/try/main/try.rb" -o /tmp/try.rb
curl -fsSL "https://raw.githubusercontent.com/tobi/try/main/lib/tui.rb" -o /tmp/tui.rb
curl -fsSL "https://raw.githubusercontent.com/tobi/try/main/lib/fuzzy.rb" -o /tmp/fuzzy.rb

# Fix shebang to use system Ruby (avoid mise conflicts)
sed -i '1s|.*|#!/usr/bin/ruby|' /tmp/try.rb

# Install to /usr/bin with lib directory
sudo install -Dm755 /tmp/try.rb /usr/bin/try
sudo mkdir -p /usr/bin/lib
sudo install -Dm644 /tmp/tui.rb /usr/bin/lib/tui.rb
sudo install -Dm644 /tmp/fuzzy.rb /usr/bin/lib/fuzzy.rb

# Cleanup
rm -f /tmp/try.rb /tmp/tui.rb /tmp/fuzzy.rb

echo "tobi-try installed successfully"
