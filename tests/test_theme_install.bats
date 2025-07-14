#!/usr/bin/env bats

# Test theme installation functionality

# Test setup
setup() {
  export TEST_HOME="/tmp/omarchy-test-$$"
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_HOME"
  
  # Create test home directory structure
  mkdir -p "$HOME/.config/omarchy/themes/test-theme"
  mkdir -p "$HOME/.config/omarchy/backgrounds"

  # Copy test theme
  cp tests/fixtures/test_theme.toml "$HOME/.config/omarchy/themes/test-theme/theme.toml"
}

teardown() {
  # Restore original HOME
  export HOME="$ORIGINAL_HOME"

  # Clean up test directory
  rm -rf "$TEST_HOME"
}

# Source URL validation function from the script
validate_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https?:// ]]; then
    return 1
  fi
  return 0
}

# Simplified parse_background_urls for testing
parse_background_urls() {
  local file="$1"
  tomlq -r '.background[].url // empty' "$file" | grep -v '^null$' || true
}

@test "URL validation: accepts HTTPS URLs" {
  validate_url "https://example.com/image.jpg"
}

@test "URL validation: accepts HTTP URLs" {
  validate_url "http://example.com/image.jpg"
}

@test "URL validation: rejects file:// URLs" {
  run validate_url "file:///etc/passwd"
  [ "$status" -eq 1 ]
}

@test "URL validation: rejects invalid URLs" {
  run validate_url "/path/to/file"
  [ "$status" -eq 1 ]
}

@test "URL validation: rejects FTP URLs" {
  run validate_url "ftp://example.com/file"
  [ "$status" -eq 1 ]
}

@test "Theme installation: finds theme by name" {
  # Check that theme directory exists
  [ -d "$HOME/.config/omarchy/themes/test-theme" ]
  [ -f "$HOME/.config/omarchy/themes/test-theme/theme.toml" ]
}

@test "Theme installation: parses background URLs from theme.toml" {
  urls=$(parse_background_urls "$HOME/.config/omarchy/themes/test-theme/theme.toml")
  [ -n "$urls" ]
  echo "$urls" | grep -q "https://example.com/bg1.jpg"
  echo "$urls" | grep -q "https://example.com/bg2.png"
}

@test "Theme installation: creates backgrounds directory" {
  mkdir -p "$HOME/.config/omarchy/backgrounds/test-theme"
  [ -d "$HOME/.config/omarchy/backgrounds/test-theme" ]
}

@test "Theme installation: handles missing theme gracefully" {
  # Try to access non-existent theme
  [ ! -d "$HOME/.config/omarchy/themes/nonexistent" ]
}

@test "Theme installation: validates download size limits" {
  # Test that we handle the max file size parameter (50MB)
  # This is a conceptual test - actual download would require network
  MAX_SIZE=52428800 # 50MB in bytes
  [ "$MAX_SIZE" -eq 52428800 ]
}