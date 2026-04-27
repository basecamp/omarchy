# archprov rules

Each `.rule` file describes one piece of hardware support, in the style of
a PKGBUILD: shell variable assignments, Bash arrays, and an optional
`post_install()` function. The runner sources each file in a subshell and
reads the variables.

## Example

```bash
# Maintainer: your name <you@example.com>
# Rule: NVIDIA discrete GPU

rulename='gpu.nvidia'
ruledesc='NVIDIA proprietary driver stack'

match_type='pci_vendor_class'
match_value='10de:0300'

depends=(nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings)

aur_depends=()
services=()
services_user=()
groups=()
kernel_params=(nvidia-drm.modeset=1)

post_install() {
    mkinitcpio -P
}
```

## Fields

The naming follows PKGBUILD conventions where it makes sense: `rulename` and
`ruledesc` mirror `pkgname` and `pkgdesc`; `depends` matches PKGBUILD exactly.

| Field                  | Type     | Purpose                                         |
|------------------------|----------|-------------------------------------------------|
| `rulename`             | string   | Unique identifier, dotted style                 |
| `ruledesc`             | string   | Human-readable description                      |
| `match_type`           | string   | How to detect — see table below                 |
| `match_value`          | string or array | Value(s) to match against                |
| `depends`              | array    | Official repo packages                          |
| `aur_depends`          | array    | AUR packages                                    |
| `services`             | array    | systemd **system** units to enable              |
| `services_user`        | array    | systemd **user** units to enable for $SUDO_USER |
| `groups`               | array    | Groups to add the user to                       |
| `kernel_params`        | array    | Kernel command-line params                      |
| `requires_reboot`      | string   | Non-empty = needs reboot; the value is the reason |
| `needs_kernel_headers` | bool     | true = pulls in matching `*-headers` for installed kernels |
| `kernel`               | string   | Specific kernel pkg this rule needs (e.g. `linux-ptl-audio`) |
| `post_install`         | function | Optional shell function run after install       |

### Kernel resolution

`needs_kernel_headers` and `kernel` solve different problems:

- **`needs_kernel_headers=true`** is for rules that ship a DKMS module
  (Razer, NVIDIA proprietary, etc.). hwtool detects which kernel(s) the
  user already has installed by enumerating `/usr/lib/modules/*/vmlinuz`
  and adds the matching `*-headers` package(s). Works with stock Arch
  kernels and Omarchy's custom ones alike.

- **`kernel='linux-X'`** is for rules whose hardware genuinely needs a
  *specific* kernel — e.g., Panther Lake audio support requires Omarchy's
  `linux-ptl-audio`. This adds both the kernel package and its headers
  to the install plan.

If two or more matched rules disagree on which kernel they need, hwtool
aborts with a conflict error rather than guessing or installing both.

Empty arrays are written `()`. Optional functions can simply be omitted.

## Match types

| `match_type`         | `match_value` format     | Detection source                         |
|----------------------|--------------------------|------------------------------------------|
| `pci_vendor`         | `'10de'`                 | `lspci -nn`                              |
| `pci_vendor_class`   | `'10de:0300'`            | `lspci -nn` (vendor + class)             |
| `cpu_vendor`         | `'AuthenticAMD'`         | `/proc/cpuinfo`                          |
| `cpu_flag`           | `'svm'`                  | `/proc/cpuinfo` flags line               |
| `dmi_vendor`         | `'LENOVO'`               | `dmidecode -s system-manufacturer`       |
| `dmi_product_regex`  | `'^ThinkPad'`            | `dmidecode -s system-product-name`       |
| `chassis_type`       | `'laptop'`               | `dmidecode -s chassis-type` (lowercased) |
| `block_device`       | `'nvme'`                 | `lsblk -d -o NAME`                       |
| `usb_vendor`         | `'1050'`                 | `lsusb` (single vendor ID)               |
| `usb_vendor_any`     | `('06cb' '27c6' '138a')` | `lsusb` (matches any in array)           |

## Adding a rule

Copy any existing `.rule` file, change `rulename` to something unique, and
edit the fields. Filename should be `<category>-<n>.rule` so `ls rules/`
gives a useful overview.

## Validating a rule

You can sanity-check the syntax without installing anything:

```bash
bash -n rules/your-new.rule           # syntax check
( source rules/your-new.rule; declare -p rulename depends )   # see parsed values
```
