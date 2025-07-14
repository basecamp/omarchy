#!/usr/bin/env bats

# Test TOML parsing functionality

# Use tomlq for TOML parsing
parse_toml_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  
  tomlq -r ".$section.$key // empty" "$file" | grep -v '^null$' || echo ""
}

parse_background_urls() {
  local file="$1"
  
  tomlq -r '.background[].url // empty' "$file" | grep -v '^null$' || true
}

# Test file
TEST_FILE="tests/fixtures/test_theme.toml"

@test "TOML parsing: parses theme name" {
  result=$(parse_toml_value "$TEST_FILE" "theme" "name")
  [ "$result" = "Test Theme" ]
}

@test "TOML parsing: parses theme variant" {
  result=$(parse_toml_value "$TEST_FILE" "theme" "variant")
  [ "$result" = "dark" ]
}

@test "TOML parsing: parses GTK theme" {
  result=$(parse_toml_value "$TEST_FILE" "gtk" "theme")
  [ "$result" = "Adwaita-dark" ]
}

@test "TOML parsing: parses GTK color scheme" {
  result=$(parse_toml_value "$TEST_FILE" "gtk" "color_scheme")
  [ "$result" = "prefer-dark" ]
}

@test "TOML parsing: parses icon theme" {
  result=$(parse_toml_value "$TEST_FILE" "icons" "theme")
  [ "$result" = "TestIcons" ]
}

@test "TOML parsing: parses cursor theme" {
  result=$(parse_toml_value "$TEST_FILE" "icons" "cursor_theme")
  [ "$result" = "TestCursor" ]
}

@test "TOML parsing: parses monospace font" {
  result=$(parse_toml_value "$TEST_FILE" "fonts" "monospace")
  [ "$result" = "Test Mono 12" ]
}

@test "TOML parsing: parses sans serif font" {
  result=$(parse_toml_value "$TEST_FILE" "fonts" "sans_serif")
  [ "$result" = "Test Sans 11" ]
}

@test "TOML parsing: parses background URLs" {
  urls=$(parse_background_urls "$TEST_FILE")
  [ -n "$urls" ]
  echo "$urls" | grep -q "https://example.com/bg1.jpg"
  echo "$urls" | grep -q "https://example.com/bg2.png"
}

@test "TOML parsing: counts background entries" {
  count=$(parse_background_urls "$TEST_FILE" | wc -l)
  [ "$count" -eq 2 ]
}

@test "TOML parsing: parses environment variables" {
  result=$(tomlq -r '.env.TEST_VAR' "$TEST_FILE")
  [ "$result" = "test_value" ]
  
  result=$(tomlq -r '.env.ANOTHER_VAR' "$TEST_FILE")
  [ "$result" = "another_value" ]
}

@test "TOML parsing: handles missing values gracefully" {
  result=$(parse_toml_value "$TEST_FILE" "nonexistent" "key")
  [ -z "$result" ]
}

@test "TOML parsing: handles missing file gracefully" {
  # tomlq should fail when file doesn't exist
  run tomlq -r '.theme.name' "/nonexistent/file.toml"
  [ "$status" -ne 0 ]
}