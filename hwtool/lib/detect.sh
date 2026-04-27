#!/bin/bash
#
# hwtool/lib/detect.sh
#
# Hardware detection. Populates global arrays/variables describing the
# system's hardware so rule matchers can check against them without
# re-running detection commands.
#
# Variables populated:
#   HW_CPU_VENDOR           string  (e.g. "GenuineIntel", "AuthenticAMD")
#   HW_CPU_FLAGS            array   (e.g. "vmx" "aes" "avx2" ...)
#   HW_PCI_VENDOR_CLASS     array   ("vendor:class" pairs, e.g. "10de:0300")
#   HW_USB_VENDORS          array   (4-char hex vendor IDs from lsusb)
#   HW_DMI_VENDOR           string  (system-manufacturer)
#   HW_DMI_PRODUCT          string  (system-product-name)
#   HW_CHASSIS_TYPE         string  (lowercased chassis type)
#   HW_BLOCK_DEVICES        array   (block device names from lsblk)
#

[[ -n "$HWTOOL_DETECT_SH" ]] && return
HWTOOL_DETECT_SH=1

# CPU --------------------------------------------------------------------------

hw_detect_cpu() {
    HW_CPU_VENDOR=$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)
    local flags_line
    flags_line=$(awk -F': ' '/^flags/ {print $2; exit}' /proc/cpuinfo)
    # shellcheck disable=SC2206
    HW_CPU_FLAGS=( $flags_line )
}

# PCI --------------------------------------------------------------------------
# Parse `lspci -nn` output. Each line ends with [vendor:device] and class
# is in [class_hex] earlier in the line.
#
# Example line:
#   01:00.0 VGA compatible controller [0300]: NVIDIA Corp. [10de:2191] (rev a1)

hw_detect_pci() {
    HW_PCI_VENDOR_CLASS=()
    if ! command -v lspci >/dev/null; then
        warning "lspci not found; PCI detection skipped (install pciutils)"
        return
    fi

    local line class vendor
    while IFS= read -r line; do
        # extract first [XXXX] which is the class
        class=$(grep -oP '\[\K[0-9a-f]{4}(?=\])' <<<"$line" | head -n1)
        # extract [vendor:device] which is the last [XXXX:XXXX] on the line
        vendor=$(grep -oP '\[\K[0-9a-f]{4}(?=:[0-9a-f]{4}\])' <<<"$line" | tail -n1)
        [[ -n "$class" && -n "$vendor" ]] && HW_PCI_VENDOR_CLASS+=("${vendor}:${class}")
    done < <(lspci -nn)
}

# USB --------------------------------------------------------------------------
# `lsusb` output looks like:
#   Bus 001 Device 003: ID 1050:0407 Yubico.com Yubikey 4 OTP+U2F+CCID

hw_detect_usb() {
    HW_USB_VENDORS=()
    HW_USB_VIDPID=()
    if ! command -v lsusb >/dev/null; then
        warning "lsusb not found; USB detection skipped (install usbutils)"
        return
    fi

    local line vidpid
    while IFS= read -r line; do
        vidpid=$(grep -oP 'ID \K[0-9a-f]{4}:[0-9a-f]{4}' <<<"$line")
        if [[ -n "$vidpid" ]]; then
            HW_USB_VIDPID+=("$vidpid")
            HW_USB_VENDORS+=("${vidpid%:*}")
        fi
    done < <(lsusb)
}

# DMI / chassis ----------------------------------------------------------------
# Prefer reading sysfs (no root needed) over dmidecode.

hw_detect_dmi() {
    HW_DMI_VENDOR=""
    HW_DMI_PRODUCT=""
    HW_CHASSIS_TYPE=""

    [[ -r /sys/class/dmi/id/sys_vendor ]] \
        && HW_DMI_VENDOR=$(cat /sys/class/dmi/id/sys_vendor)
    [[ -r /sys/class/dmi/id/product_name ]] \
        && HW_DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name)

    # chassis_type is a small integer; map the relevant ones
    # see SMBIOS spec section 7.4.1
    local raw=""
    [[ -r /sys/class/dmi/id/chassis_type ]] \
        && raw=$(cat /sys/class/dmi/id/chassis_type)
    case "$raw" in
        8|9|10|11|14)  HW_CHASSIS_TYPE="laptop" ;;
        3|4|5|6|7|15)  HW_CHASSIS_TYPE="desktop" ;;
        17|23|25)      HW_CHASSIS_TYPE="server" ;;
        *)             HW_CHASSIS_TYPE="unknown" ;;
    esac
}

# Block devices ----------------------------------------------------------------

hw_detect_block() {
    HW_BLOCK_DEVICES=()
    local name
    while IFS= read -r name; do
        HW_BLOCK_DEVICES+=("$name")
    done < <(lsblk -d -n -o NAME 2>/dev/null)
}

# Run all -----------------------------------------------------------------------

hw_detect_all() {
    hw_detect_cpu
    hw_detect_pci
    hw_detect_usb
    hw_detect_dmi
    hw_detect_block
}

# Pretty-print what we detected (for --show-hardware)

hw_show() {
    msg "Detected hardware"
    msg2 "CPU vendor: %s" "${HW_CPU_VENDOR:-unknown}"
    msg2 "CPU flags: %d (%s ...)" "${#HW_CPU_FLAGS[@]}" "${HW_CPU_FLAGS[*]:0:8}"
    msg2 "PCI devices: %d" "${#HW_PCI_VENDOR_CLASS[@]}"
    msg2 "USB devices: %d" "${#HW_USB_VENDORS[@]}"
    msg2 "DMI vendor: %s" "${HW_DMI_VENDOR:-unknown}"
    msg2 "DMI product: %s" "${HW_DMI_PRODUCT:-unknown}"
    msg2 "Chassis: %s" "$HW_CHASSIS_TYPE"
    msg2 "Block devices: %s" "${HW_BLOCK_DEVICES[*]}"
}
