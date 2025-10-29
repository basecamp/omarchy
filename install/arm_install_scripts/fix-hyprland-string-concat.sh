#!/bin/bash
# Fix GCC 14 compatibility issues in Hyprland source code
# GCC 14 has stricter type deduction rules than GCC 15 in several areas

set -e

if [[ ! -f "hyprctl/main.cpp" ]]; then
    echo "ERROR: Must be run from Hyprland source directory"
    echo "  (hyprctl/main.cpp not found)"
    exit 1
fi

if [[ ! -f "src/xwayland/XWM.hpp" ]]; then
    echo "ERROR: Must be run from Hyprland source directory"
    echo "  (src/xwayland/XWM.hpp not found)"
    exit 1
fi

if [[ ! -f "src/helpers/Monitor.cpp" ]]; then
    echo "ERROR: Must be run from Hyprland source directory"
    echo "  (src/helpers/Monitor.cpp not found)"
    exit 1
fi

echo "=== Fixing GCC 14 Compatibility Issues ==="
echo ""
echo "1. String concatenation template deduction (hyprctl/main.cpp)..."

# Create backup
cp hyprctl/main.cpp hyprctl/main.cpp.orig

# Show what we're looking for
echo "  Searching for string concatenation patterns in hyprctl/main.cpp..."
grep -n 'getRuntimeDir() + "/" +' hyprctl/main.cpp || echo "  (Pattern 1 & 2 not found with grep)"
grep -n 'fullArgs + "/" +' hyprctl/main.cpp || echo "  (Pattern 3 not found with grep)"

# Fix pattern 1: getRuntimeDir() + "/" + instanceSignature + "/.socket.sock"
# Break into completely separate appends - NO chained + operators at all
echo "  Applying fix 1: .socket.sock pattern..."
sed -i 's|std::string socketPath = getRuntimeDir() + "/" + instanceSignature + "/.socket.sock";|std::string socketPath = getRuntimeDir();\n    socketPath += "/";\n    socketPath += instanceSignature;\n    socketPath += "/.socket.sock";|' hyprctl/main.cpp

# Fix pattern 2: getRuntimeDir() + "/" + instanceSignature + "/" + filename
# Break into completely separate appends - NO chained + operators at all
echo "  Applying fix 2: filename pattern..."
sed -i 's|std::string socketPath = getRuntimeDir() + "/" + instanceSignature + "/" + filename;|std::string socketPath = getRuntimeDir();\n        socketPath += "/";\n        socketPath += instanceSignature;\n        socketPath += "/";\n        socketPath += filename;|' hyprctl/main.cpp

# Fix pattern 3: fullRequest = fullArgs + "/" + fullRequest
# Break into completely separate appends - NO chained + operators at all
echo "  Applying fix 3: fullRequest pattern..."
sed -i 's|fullRequest          = fullArgs + "/" + fullRequest;|fullArgs += "/";\n        fullArgs += fullRequest;\n        fullRequest = fullArgs;|' hyprctl/main.cpp

# Verify changes were made
echo ""
echo "Checking if patterns were replaced..."
if diff -q hyprctl/main.cpp hyprctl/main.cpp.orig >/dev/null 2>&1; then
  echo "  WARNING: No changes were made to hyprctl/main.cpp!"
  echo "  This means the patterns don't match the source code."
  echo "  Showing diff context around line 273:"
  sed -n '270,280p' hyprctl/main.cpp.orig
  exit 1
else
  echo "  ✓ File was modified"
fi

echo "✓ Fixed string concatenation patterns in hyprctl/main.cpp"
echo "  Original saved as: hyprctl/main.cpp.orig"

echo ""
echo "2. Ternary operator type deduction (src/xwayland/XWM.hpp)..."

# Create backup
cp src/xwayland/XWM.hpp src/xwayland/XWM.hpp.orig

# Fix ternary operator where GCC 14 can't deduce common type between dereferenced
# pointer and nullptr. Need to explicitly cast nullptr to the pointer type.
# Before: return m_connection ? *m_connection : nullptr;
# After:  return m_connection ? *m_connection : static_cast<xcb_connection_t*>(nullptr);

echo "  Searching for ternary operator pattern in XWM.hpp..."
grep -n 'return m_connection ? \*m_connection : nullptr;' src/xwayland/XWM.hpp || echo "  (Pattern not found with grep)"

echo "  Applying ternary operator fix..."
sed -i 's|return m_connection ? \*m_connection : nullptr;|return m_connection ? *m_connection : static_cast<xcb_connection_t*>(nullptr);|' src/xwayland/XWM.hpp

# Verify changes
echo ""
echo "Checking if XWM.hpp was modified..."
if diff -q src/xwayland/XWM.hpp src/xwayland/XWM.hpp.orig >/dev/null 2>&1; then
  echo "  WARNING: No changes were made to src/xwayland/XWM.hpp!"
  echo "  This means the pattern doesn't match the source code."
  echo "  Showing diff context around line 216:"
  sed -n '213,220p' src/xwayland/XWM.hpp.orig
  exit 1
else
  echo "  ✓ File was modified"
fi

echo "✓ Fixed ternary operator pattern in src/xwayland/XWM.hpp"
echo "  Original saved as: src/xwayland/XWM.hpp.orig"

echo ""
echo "3. C++23 insert_range (src/helpers/Monitor.cpp)..."

# Create backup
cp src/helpers/Monitor.cpp src/helpers/Monitor.cpp.orig

# Fix insert_range() which is a C++23 feature not available in GCC 14's libstdc++
# Before: requestedModes.insert_range(requestedModes.end(), sortedModes | std::views::reverse);
# After:  std::ranges::copy(sortedModes | std::views::reverse, std::back_inserter(requestedModes));

echo "  Searching for insert_range pattern in Monitor.cpp..."
grep -n 'insert_range' src/helpers/Monitor.cpp || echo "  (Pattern not found with grep)"

echo "  Applying C++23 -> C++20 compatibility fix..."
sed -i 's#requestedModes\.insert_range(requestedModes\.end(), sortedModes | std::views::reverse);#std::ranges::copy(sortedModes | std::views::reverse, std::back_inserter(requestedModes));#' src/helpers/Monitor.cpp

# Verify changes
echo ""
echo "Checking if Monitor.cpp was modified..."
if diff -q src/helpers/Monitor.cpp src/helpers/Monitor.cpp.orig >/dev/null 2>&1; then
  echo "  WARNING: No changes were made to src/helpers/Monitor.cpp!"
  echo "  This means the pattern doesn't match the source code."
  echo "  Showing diff context around line 604:"
  sed -n '600,610p' src/helpers/Monitor.cpp.orig
  exit 1
else
  echo "  ✓ File was modified"
fi

echo "✓ Fixed C++23 insert_range in src/helpers/Monitor.cpp"
echo "  Original saved as: src/helpers/Monitor.cpp.orig"

echo ""
echo "=== All GCC 14 Compatibility Fixes Applied ==="
echo "  ✓ String concatenation template deduction (3 patterns)"
echo "  ✓ Ternary operator type deduction (1 pattern)"
echo "  ✓ C++23 insert_range -> C++20 ranges::copy (1 pattern)"
