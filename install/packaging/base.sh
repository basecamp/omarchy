
# Read core and optional packages from omarchy-base.packages
core_packages=()
optional_packages=()
in_optional=0
while IFS= read -r line; do
	[[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
	if [[ "$line" == "OPTIONAL:" ]]; then
		in_optional=1
		continue
	fi
	if (( in_optional )); then
		optional_packages+=("$line")
	else
		core_packages+=("$line")
	fi
done < "$OMARCHY_INSTALL/omarchy-base.packages"

# Interactive selection for optional packages using gum
if command -v gum &>/dev/null && (( ${#optional_packages[@]} > 0 )); then
	echo "\e[34m[Omarchy] Select optional packages to install (use space to select, enter to confirm):\e[0m"
	selected_optional=$(printf '%s\n' "${optional_packages[@]}" | gum choose --no-limit --height 20)
	mapfile -t selected_optional_pkgs <<< "$selected_optional"
else
	selected_optional_pkgs=("${optional_packages[@]}")
fi

# Combine core and selected optional packages
packages=("${core_packages[@]}" "${selected_optional_pkgs[@]}")

# Pre-Install Compatibility Check
echo "\e[34m[Omarchy] Checking package availability...\e[0m"
unavailable_pkgs=()
for pkg in "${packages[@]}"; do
	if ! check_package_availability "$pkg"; then
		unavailable_pkgs+=("$pkg")
	fi
done
if (( ${#unavailable_pkgs[@]} > 0 )); then
	echo "\e[33m[Warning] The following packages are likely unavailable and will be skipped:\e[0m"
	for pkg in "${unavailable_pkgs[@]}"; do
		echo "  - $pkg"
	done
	echo
fi

# Install all base packages, trying AUR helpers as fallbacks
failed_packages=()
for pkg in "${packages[@]}"; do
	if check_package_availability "$pkg"; then
		if ! try_install_package "$pkg"; then
			failed_packages+=("$pkg")
		fi
	else
		echo "[SKIPPED] $pkg (not available)"
		failed_packages+=("$pkg (not available)")
	fi
done

# Post-install summary and support
echo
if (( ${#failed_packages[@]} > 0 )); then
	echo "==============================="
	echo "The following packages could not be installed:"
	for pkg in "${failed_packages[@]}"; do
		echo "  - $pkg"
	done
	echo "==============================="
	echo "If you need help or want to request support for missing packages, contact @tiredkebab on X (Twitter)."
else
	echo "\e[32mAll packages installed successfully!\e[0m"
fi

echo
echo "[Omarchy] Installation complete. For troubleshooting, see the install log. For support, contact @tiredkebab on X (Twitter)."
