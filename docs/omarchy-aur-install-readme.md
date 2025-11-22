# omarchy-aur-install

A fully autonomous AUR helper script with intelligent dependency resolution, automatic fallback to GitHub mirror, and zero user interaction required.

## Overview

`omarchy-aur-install` is a robust AUR package installer designed for automated environments and ARM-based systems. It handles complex dependency chains, split packages, and gracefully falls back to GitHub's AUR mirror when the official AUR is unavailable.

## Features

### 🤖 Fully Autonomous
- **Zero prompts**: Automatically selects first provider, confirms all operations
- **No manual intervention**: Handles conflicts, dependencies, and split packages automatically
- **Unattended installs**: Perfect for scripts and automation

### 🔍 Intelligent Dependency Resolution
- **Recursive resolution**: Automatically finds and installs AUR dependencies
- **Smart detection**: Distinguishes between official repo, AUR, and virtual provides
- **Library handling**: Correctly processes `.so` virtual provides (e.g., `libfontconfig.so`)
- **Split package support**: Handles split packages with hardcoded mappings + RPC discovery
- **Architecture-aware**: Extracts and processes arch-specific dependencies

### 🌐 Automatic AUR Fallback
- **Health monitoring**: Tracks AUR availability with configurable thresholds
- **GitHub mirror**: Automatically switches to GitHub AUR mirror when needed
- **Cooldown system**: Prevents hammering AUR when it's experiencing issues
- **Retry logic**: Intelligent retry with exponential backoff

### 🛡️ ARM-Optimized
- **Auto --ignorearch**: Automatically adds flag for ARM systems
- **Flaky test handling**: Skips known problematic tests on ARM VMs
- **Hardcoded mappings**: Pre-configured for common split packages

## Installation

The script is already installed at:
```
~/.local/share/omarchy/bin/omarchy-aur-install
```

Ensure `~/.local/share/omarchy/bin` is in your `$PATH`.

## Usage

### Basic Installation
```bash
omarchy-aur-install <package-name>
```

### Multiple Packages
```bash
omarchy-aur-install package1 package2 package3
```

### With Custom Makepkg Flags
```bash
omarchy-aur-install --makepkg-flags='--needed' package-name
```

### Examples
```bash
# Install single package
omarchy-aur-install ghostty-git

# Install multiple packages
omarchy-aur-install yay paru

# Install with custom flags
omarchy-aur-install --makepkg-flags='--needed --nocheck'some-package
```

## How It Works

### 1. Dependency Resolution Phase
```
For each package:
  ├─ Clone PKGBUILD from AUR
  ├─ Extract depends + makedepends (including arch-specific)
  ├─ For each dependency:
  │   ├─ Skip if .so library (virtual provide)
  │   ├─ Skip if already satisfied (pacman -T)
  │   ├─ Skip if in official repos (pacman -Sp)
  │   └─ Recursively resolve if AUR package
  └─ Build dependency tree
```

### 2. Build & Install Phase
```
For each package in dependency order:
  ├─ Check if already satisfied (skip duplicates)
  ├─ Handle split packages (PackageBase discovery)
  ├─ Clone repository (AUR or GitHub mirror)
  ├─ Pre-build conflict removal
  ├─ Build with makepkg -si --noconfirm
  └─ Auto-select first provider (printf '1' | makepkg)
```

## Key Differences from Other AUR Helpers

| Feature | omarchy-aur-install | yay/paru |
|---------|---------------------|----------|
| Fully autonomous | ✅ Zero prompts | ⚠️ Some prompts |
| GitHub mirror fallback | ✅ Automatic | ❌ No |
| ARM optimization | ✅ Built-in | ⚠️ Manual flags |
| Library .so handling | ✅ Automatic | ✅ Yes |
| Split package detection | ✅ Hardcoded + RPC | ✅ Yes |
| AUR health monitoring | ✅ With cooldown | ❌ No |
| Provider auto-select | ✅ Always first | ⚠️ Prompts user |

## Configuration

### Environment Variables

**Enable Debug Mode:**
```bash
export OMARCHY_AUR_DEBUG=1
omarchy-aur-install package-name
```

**Simulate AUR Down (Testing):**
```bash
export OMARCHY_SIMULATE_AUR_DOWN=1
omarchy-aur-install package-name  # Will use GitHub mirror
```

### Hardcoded Settings (in script)

Located at top of script:
```bash
AUR_CHECK_TIMEOUT=5              # Seconds to wait for AUR health check
AUR_FAILURE_THRESHOLD=3          # Failures before marking AUR as down
AUR_COOLDOWN_MINUTES=20          # Minutes before retrying AUR
```

### Split Package Mappings

Add to `KNOWN_SPLIT_PACKAGES` array (line 48):
```bash
declare -A KNOWN_SPLIT_PACKAGES=(
  ["package-name"]="package-base"
  ["yaru-icon-theme"]="yaru"
)
```

### ARM Flaky Tests

Add to `SKIP_TESTS_ON_ARM` array (line 64):
```bash
declare -A SKIP_TESTS_ON_ARM=(
  ["package-name"]="reason for skipping"
  ["ruby-stud"]="timing tests flaky on ARM VMs"
)
```

## Troubleshooting

### Package Not Found

**Error:** "Package 'xyz' not found in AUR or official repositories"

**Solution:**
1. Verify package name: `curl -s 'https://aur.archlinux.org/rpc/?v=5&type=search&arg=xyz'`
2. Check if it's in official repos: `pacman -Ss xyz`
3. Try GitHub mirror: `export OMARCHY_SIMULATE_AUR_DOWN=1`

### Build Failures

**Error:** "Failed to build/install 'package'"

**Common causes:**
- Missing system dependencies → Install with `pacman -S`
- Outdated Zig/toolchain → Update build tools
- Architecture mismatch → Script auto-handles with `--ignorearch`

**Debug:**
```bash
export OMARCHY_AUR_DEBUG=1
omarchy-aur-install package-name
```

### Split Package Issues

**Error:** "Clone failed for 'package', checking if this is a split package..."

**Solution:** Add to hardcoded mappings if RPC discovery fails:
```bash
# Edit script, add to KNOWN_SPLIT_PACKAGES array
["your-package"]="actual-package-base"
```

### AUR Connection Issues

**Error:** "AUR is unreachable (timeout: 5s)"

**Behavior:**
- Script automatically falls back to GitHub mirror
- After 3 failures, AUR marked as down for 20 minutes
- Check status: `cat /tmp/omarchy-aur-state-$(id -u)`

**Manual override:**
```bash
# Force AUR usage
rm /tmp/omarchy-aur-state-$(id -u)

# Force GitHub mirror
export OMARCHY_SIMULATE_AUR_DOWN=1
```

## Advanced Usage

### Batch Installation
```bash
# Install from list
cat packages.txt | xargs omarchy-aur-install

# With error handling
while read pkg; do
  omarchy-aur-install "$pkg" || echo "Failed: $pkg" >> failed.txt
done < packages.txt
```

### Custom Makepkg Configuration
```bash
# Skip tests and use all cores
omarchy-aur-install --makepkg-flags='--nocheck -r' package-name
```

### Scripted Installation
```bash
#!/bin/bash
set -e

packages=(
  "ghostty-git"
  "yay"
  "visual-studio-code-bin"
)

for pkg in "${packages[@]}"; do
  echo "Installing $pkg..."
  omarchy-aur-install "$pkg"
done
```

## Technical Details

### Dependency Detection Logic

1. **Extract from PKGBUILD:**
   - Sources PKGBUILD in subshell with `CARCH` set
   - Extracts: `depends`, `makedepends`, `depends_${CARCH}`, `makedepends_${CARCH}`

2. **Filter Dependencies:**
   ```bash
   For each dependency:
     If contains '.so' → SKIP (library/virtual provide)
     Strip version (>=, =, <) → Check satisfaction
     If pacman -T satisfied → SKIP
     If pacman -Sp found → SKIP (official repo)
     Else → Resolve from AUR
   ```

3. **Handle Virtual Provides:**
   - `libfontconfig.so` → Provided by `fontconfig` (official)
   - `pandoc-cli` → Provided by `pandoc-bin` (AUR)
   - Detection via `pacman -T` (checks installed provides)

### Provider Selection

Automatically selects first option:
```bash
printf '1\n%.0s' {1..100} | makepkg -si --noconfirm
```

Handles up to 100 provider prompts per build (far exceeds real-world scenarios).

### Conflict Resolution

Pre-build conflict removal:
```bash
1. Extract conflicts from .SRCINFO
2. Check if conflicting package installed
3. Remove with: sudo pacman -Rdd --noconfirm
4. Proceed with build
```

## Limitations

1. **AUR RPC Rate Limiting**: Heavy usage may trigger rate limits (no backoff implemented)
2. **No GPG Verification**: PKGBUILDs are trusted without signature verification
3. **No PKGBUILD Inspection**: Doesn't warn about potentially malicious commands
4. **Network Dependency**: Requires internet for AUR/GitHub access

These are inherent to AUR helper design and acceptable for most use cases.

## Security Considerations

**This script executes PKGBUILDs from AUR with sudo privileges.** Best practices:

1. Only install packages from trusted maintainers
2. Review AUR comments for issues: `https://aur.archlinux.org/packages/<name>`
3. Inspect PKGBUILD before building: `https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=<name>`
4. Use AUR package popularity as a trust signal
5. Enable debug mode for suspicious packages: `OMARCHY_AUR_DEBUG=1`

## Files & Directories

```
~/.local/share/omarchy/bin/omarchy-aur-install  # Main script
/tmp/aur-build-*                                # Temporary build dirs
/tmp/aur-dep-check-*                            # Dependency resolution temp
/tmp/omarchy-aur-state-$(id -u)                 # AUR health status
```

Build directories are automatically cleaned up on success or failure.

## Version History

- **Current**: Fixed `.so` library handling, added pre-discovery optimization
- **Previous**: Initial release with basic AUR installation + GitHub fallback

## Contributing

To report issues or suggest improvements:
1. Test with debug mode: `OMARCHY_AUR_DEBUG=1 omarchy-aur-install package`
2. Check existing hardcoded mappings (line 48-66)
3. Document reproduction steps and expected behavior

## License

Part of the Omarchy project. See project root for license details.

## See Also

- [Ghostty ARM VM Installation Guide](./ghostty-arm-vm-install-guide.md)
- [AUR Official Documentation](https://wiki.archlinux.org/title/Arch_User_Repository)
- [GitHub AUR Mirror](https://github.com/archlinux/aur)
