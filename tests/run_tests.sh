#!/bin/bash

# Test runner for omarchy theme tests using BATS

# Colors
BOLD='\033[1m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# Change to project root
cd "$(dirname "$0")/.."

# Check if BATS is installed
if ! command -v bats &>/dev/null; then
  echo -e "${RED}Error: BATS is not installed${NC}"
  echo "Install it with: yay -S bats"
  exit 1
fi

# Check if tomlq is installed (required for tests)
if ! command -v tomlq &>/dev/null; then
  echo -e "${RED}Error: tomlq is not installed${NC}"
  echo "Install it with: yay -S yq"
  exit 1
fi

# Make test scripts executable
chmod +x tests/*.bats

# Run all BATS tests
if [ $# -eq 0 ]; then
  # Run all tests
  bats tests/*.bats
else
  # Run specific test file(s)
  bats "$@"
fi

# Capture exit status
EXIT_STATUS=$?

# Summary
if [ $EXIT_STATUS -eq 0 ]; then
  echo -e "\n${GREEN}✓ All tests passed!${NC}"
else
  echo -e "\n${RED}✗ Some tests failed${NC}"
fi

exit $EXIT_STATUS

