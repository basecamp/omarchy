# Omarchy Theme System Tests

This directory contains tests for the theme system's TOML-based configuration using BATS (Bash Automated Testing System).

## Prerequisites

Install the required dependencies:
```bash
yay -S bats yq
```

## Running Tests

To run all tests:
```bash
./tests/run_tests.sh
```

To run specific test files:
```bash
./tests/run_tests.sh tests/test_toml_parser.bats
```

To run tests matching a pattern:
```bash
bats tests/ --filter "light theme"
```

## Test Suites

### 1. TOML Parser Tests (`test_toml_parser.bats`)
- Tests the TOML parsing functionality
- Validates parsing of all theme configuration sections
- Tests edge cases like missing values

### 2. Theme Installation Tests (`test_theme_install.bats`)
- Tests URL validation for security
- Tests theme directory resolution
- Tests resource installation logic

### 3. Theme Configuration Tests (`test_theme_toml.bats`)
- Tests theme loading from TOML files
- Validates light vs dark theme configurations
- Tests required sections and values

## Writing Tests

BATS tests use a simple syntax:

```bash
#!/usr/bin/env bats

@test "description of what you're testing" {
  # Arrange
  setup_test_data
  
  # Act
  result=$(function_to_test)
  
  # Assert
  [ "$result" = "expected value" ]
}
```

### Common Assertions

```bash
# Check equality
[ "$actual" = "expected" ]

# Check if string contains substring
echo "$output" | grep -q "substring"

# Check command success
run some_command
[ "$status" -eq 0 ]

# Check command failure
run failing_command
[ "$status" -ne 0 ]

# Check file/directory exists
[ -f "/path/to/file" ]
[ -d "/path/to/directory" ]
```

### Setup and Teardown

Use `setup()` and `teardown()` functions for test preparation and cleanup:

```bash
setup() {
  export TEST_DIR="$(mktemp -d)"
  # Create test data
}

teardown() {
  rm -rf "$TEST_DIR"
}
```

## Debugging Tests

Run tests with more verbose output:
```bash
bats --trace tests/test_file.bats
```

Show output even for passing tests:
```bash
bats --print-output-on-failure tests/
```

## CI Integration

For GitHub Actions or other CI systems:

```yaml
- name: Install test dependencies
  run: |
    sudo pacman -S --noconfirm bats
    yay -S --noconfirm yq

- name: Run tests
  run: ./tests/run_tests.sh
```

## Test Coverage

Current test coverage includes:
- ✅ TOML parsing for all theme sections
- ✅ URL validation for security
- ✅ Theme directory resolution
- ✅ Light/dark theme configuration
- ✅ Background URL parsing
- ✅ Environment variable handling

## Contributing

When adding new features, please include corresponding tests:
1. Create a new `.bats` file or add to existing ones
2. Test both success and failure cases
3. Use descriptive test names
4. Keep tests focused and isolated