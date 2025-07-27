#!/bin/bash
# Test script that simulates a real installation task with various outputs
# Used when TEST_MODE=true to test the installer without running real commands

# Accept step name as parameter
STEP_NAME="${1:-Generic Task}"

# Simulate different types of output based on the step name
echo "Initializing $STEP_NAME..."
sleep 0.2

# Common installation patterns
echo "Checking dependencies..."
sleep 0.3

# Simulate package-specific output
if [[ "$STEP_NAME" == *"packages"* ]] || [[ "$STEP_NAME" == *"Updating"* ]]; then
    echo "Synchronizing package databases..."
    sleep 0.4
    echo ":: Starting full system upgrade..."
    sleep 0.3
    echo "resolving dependencies..."
    sleep 0.2
    echo "looking for conflicting packages..."
    sleep 0.3
elif [[ "$STEP_NAME" == *"config"* ]] || [[ "$STEP_NAME" == *"Config:"* ]]; then
    echo "Reading configuration files..."
    sleep 0.2
    echo "Applying system settings..."
    sleep 0.3
    echo "Creating configuration backups..."
    sleep 0.2
elif [[ "$STEP_NAME" == *"development"* ]] || [[ "$STEP_NAME" == *"Development:"* ]]; then
    echo "Installing development tools..."
    sleep 0.3
    echo "Setting up build environment..."
    sleep 0.4
    echo "Configuring toolchains..."
    sleep 0.3
elif [[ "$STEP_NAME" == *"desktop"* ]] || [[ "$STEP_NAME" == *"Desktop:"* ]]; then
    echo "Setting up desktop environment..."
    sleep 0.3
    echo "Installing window manager components..."
    sleep 0.4
    echo "Configuring display settings..."
    sleep 0.2
fi

# Show some progress
echo "Processing files..."
sleep 0.2

# Simulate file operations
for i in {1..3}; do
    echo "  -> Processing item $i of 3..."
    sleep 0.3
done

# Environment variables test
if [[ -n "$OMARCHY_USER_NAME" ]]; then
    echo "Configuring for user: $OMARCHY_USER_NAME"
    sleep 0.2
fi

if [[ -n "$OMARCHY_USER_EMAIL" ]]; then
    echo "Setting email: $OMARCHY_USER_EMAIL"
    sleep 0.2
fi

# Final steps
echo "Running post-install hooks..."
sleep 0.3

echo "Cleaning up temporary files..."
sleep 0.2

echo "$STEP_NAME completed successfully!"