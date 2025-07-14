#!/usr/bin/env bats

# Test theme configuration loading

# Test setup
setup() {
  export TEST_DIR="/tmp/omarchy-toml-test-$$"
  mkdir -p "$TEST_DIR/theme-with-toml"
  mkdir -p "$TEST_DIR/theme-without-toml"

  # Create theme with TOML
  cp tests/fixtures/test_theme.toml "$TEST_DIR/theme-with-toml/theme.toml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Simulate the theme configuration loading logic
load_theme_config() {
  local theme_dir="$1"
  local theme_toml="$theme_dir/theme.toml"

  if [[ -f "$theme_toml" ]]; then
    echo "Loading from TOML"
    # Parse with tomlq
    local gtk_theme=$(tomlq -r '.gtk.theme' "$theme_toml")
    echo "gtk_theme=$gtk_theme"
  else
    echo "No theme.toml found"
    return 1
  fi
}

@test "Theme loading: loads from TOML file when exists" {
  result=$(load_theme_config "$TEST_DIR/theme-with-toml")
  echo "$result" | grep -q "Loading from TOML"
}

@test "Theme loading: extracts GTK theme value" {
  result=$(load_theme_config "$TEST_DIR/theme-with-toml")
  echo "$result" | grep -q "gtk_theme=Adwaita-dark"
}

@test "Theme loading: fails when theme.toml missing" {
  run load_theme_config "$TEST_DIR/theme-without-toml"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "No theme.toml found"
}

@test "Theme configuration: has all required sections" {
  toml_file="$TEST_DIR/theme-with-toml/theme.toml"
  
  # Check theme section
  theme_name=$(tomlq -r '.theme.name' "$toml_file")
  [ "$theme_name" = "Test Theme" ]
  
  # Check gtk section
  gtk_theme=$(tomlq -r '.gtk.theme' "$toml_file")
  [ -n "$gtk_theme" ]
  
  # Check icons section
  icon_theme=$(tomlq -r '.icons.theme' "$toml_file")
  [ -n "$icon_theme" ]
}

@test "Light theme configuration: has light-specific settings" {
  # Create a light theme config
  cat > "$TEST_DIR/light-theme.toml" <<EOF
[theme]
name = "Light Theme"
variant = "light"

[gtk]
theme = "Adwaita"
color_scheme = "prefer-light"

[env]
GTK_THEME_VARIANT = "light"
EOF

  variant=$(tomlq -r '.theme.variant' "$TEST_DIR/light-theme.toml")
  [ "$variant" = "light" ]
  
  gtk_theme=$(tomlq -r '.gtk.theme' "$TEST_DIR/light-theme.toml")
  [ "$gtk_theme" = "Adwaita" ]
  
  color_scheme=$(tomlq -r '.gtk.color_scheme' "$TEST_DIR/light-theme.toml")
  [ "$color_scheme" = "prefer-light" ]
  
  env_var=$(tomlq -r '.env.GTK_THEME_VARIANT' "$TEST_DIR/light-theme.toml")
  [ "$env_var" = "light" ]
}

@test "Dark theme configuration: has dark-specific settings" {
  toml_file="$TEST_DIR/theme-with-toml/theme.toml"
  
  variant=$(tomlq -r '.theme.variant' "$toml_file")
  [ "$variant" = "dark" ]
  
  gtk_theme=$(tomlq -r '.gtk.theme' "$toml_file")
  [ "$gtk_theme" = "Adwaita-dark" ]
  
  color_scheme=$(tomlq -r '.gtk.color_scheme' "$toml_file")
  [ "$color_scheme" = "prefer-dark" ]
}