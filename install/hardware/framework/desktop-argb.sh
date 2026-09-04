# Install framework-system for Framework Desktop ARGB fan RGB control.
#
# framework_tool needs root to read SMBIOS data even for simple RGB fan
# operations. Passwordless sudo is granted only to /usr/bin/omarchy-framework-tool-rgb,
# a root-owned wrapper that whitelists exactly the --rgbkbd fan operation; the
# rule ships with the omarchy-settings package via etc/sudoers.d/omarchy-framework-tool,
# so existing installs pick it up on the next omarchy update.

if omarchy-hw-framework-desktop; then
  omarchy-pkg-add framework-system
fi
