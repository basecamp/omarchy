# Install framework-system for Framework Desktop ARGB fan RGB control.
#
# framework_tool needs root to read SMBIOS data even for simple RGB fan
# operations. Passwordless sudo for /usr/bin/framework_tool is shipped by
# the omarchy-settings package via etc/sudoers.d/omarchy-framework-tool,
# so existing installs pick it up on the next omarchy update.

if omarchy-hw-framework-desktop; then
  omarchy-pkg-add framework-system
fi
