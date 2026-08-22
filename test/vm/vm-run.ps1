# Desktop Mode guest VM helper
#
# Portable QEMU launcher for the Ultimate Desktop Mode windowing go/no-go
# (overlapping float, drag, resize, maximize, minimize/restore identity,
# snap, Show Desktop, Alt+Tab). Acceptance screenshots are collected by the
# in-guest suite under the ISO harness; this script only boots a machine.
#
# On a Windows host the usual layout is C:\dev\omarchy-vm with an Arch disk
# and this script copied or invoked from the repo:
#
#   pwsh -File test/vm/vm-run.ps1 -Disk C:\dev\omarchy-vm\arch.qcow2
#
# TCG is the default so it runs without KVM/WHPX. Pass -Accel kvm or
# -Accel whpx when the host can use it. Shut the VM down when idle rather
# than leaving a guest running overnight.

[CmdletBinding()]
param(
  [string]$Disk = $(if ($env:OMARCHY_VM_DISK) { $env:OMARCHY_VM_DISK } else { "" }),
  [string]$Iso = $(if ($env:OMARCHY_VM_ISO) { $env:OMARCHY_VM_ISO } else { "" }),
  [int]$MemoryMb = 4096,
  [int]$Cpus = 4,
  [string]$Accel = "tcg",
  [string]$ScreenshotDir = $(if ($env:OMARCHY_VM_SCREENSHOTS) { $env:OMARCHY_VM_SCREENSHOTS } else { "" }),
  [switch]$Headless,
  [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-Qemu {
  $names = @("qemu-system-x86_64", "qemu-system-x86_64.exe")
  foreach ($name in $names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  $windowsDefault = "C:\Program Files\qemu\qemu-system-x86_64.exe"
  if (Test-Path -LiteralPath $windowsDefault) { return $windowsDefault }
  throw "qemu-system-x86_64 is not on PATH. Install QEMU and retry."
}

function Find-OvmfCode {
  $candidates = @(
    "C:\Program Files\qemu\share\edk2-x86_64-code.fd",
    "/usr/share/edk2/x64/OVMF_CODE.fd",
    "/usr/share/OVMF/OVMF_CODE.fd",
    "/usr/share/qemu/edk2-x86_64-code.fd"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return ""
}

if (-not $Disk -and -not $Iso) {
  $candidates = @(
    (Join-Path $PSScriptRoot "arch.qcow2"),
    (Join-Path $PSScriptRoot "disk.qcow2")
  )
  if ($env:OS -eq "Windows_NT") {
    $candidates += @("C:\dev\omarchy-vm\omarchy-test.qcow2", "C:\dev\omarchy-vm\arch.qcow2", "C:\dev\omarchy-vm\disk.qcow2")
  }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      $Disk = $candidate
      break
    }
  }
}

if ($ListOnly) {
  Write-Output "qemu=$(Find-Qemu)"
  Write-Output "disk=$Disk"
  Write-Output "iso=$Iso"
  Write-Output "accel=$Accel"
  Write-Output "memoryMb=$MemoryMb"
  Write-Output "cpus=$Cpus"
  Write-Output "screenshotDir=$ScreenshotDir"
  exit 0
}

if (-not $Disk -and -not $Iso) {
  throw "Pass -Disk <qcow2> or -Iso <iso>, or set OMARCHY_VM_DISK / OMARCHY_VM_ISO."
}

$qemu = Find-Qemu
$ovmf = Find-OvmfCode
# virtio-vga's default EDID prefers 640x480@240 and xres=1280,yres=800. Pin 1080p
# so Hyprland `preferred` is a real work area, and zoom the GTK window to that FB.
$args = @(
  "-machine", "q35",
  "-cpu", "max",
  "-smp", "$Cpus",
  "-m", "$MemoryMb",
  "-accel", $Accel,
  "-device", "virtio-vga,xres=1920,yres=1080",
  "-display", $(if ($Headless) { "none" } else { "gtk,zoom-to-fit=on" }),
  "-device", "qemu-xhci",
  "-device", "usb-tablet",
  "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22",
  "-device", "virtio-net-pci,netdev=net0"
)

if ($ovmf) {
  $varsDir = if ($Disk) { [System.IO.Path]::GetDirectoryName($Disk) } else { $PSScriptRoot }
  $vars = Join-Path $varsDir "ovmf-vars.fd"
  $varsSrc = Join-Path ([System.IO.Path]::GetDirectoryName($ovmf)) "edk2-i386-vars.fd"
  if (-not (Test-Path -LiteralPath $varsSrc)) {
    $varsSrc = Join-Path ([System.IO.Path]::GetDirectoryName($ovmf)) "OVMF_VARS.fd"
  }
  if ((Test-Path -LiteralPath $varsSrc) -and -not (Test-Path -LiteralPath $vars) -and $Disk) {
    Copy-Item -LiteralPath $varsSrc -Destination $vars
  }
  $args += @(
    "-drive", "if=pflash,format=raw,readonly=on,file=$ovmf"
  )
  if (Test-Path -LiteralPath $vars) {
    $args += @("-drive", "if=pflash,format=raw,file=$vars")
  }
} else {
  Write-Warning "No OVMF firmware found. systemd-boot guests will not start without -drive if=pflash edk2/OVMF code."
}

if ($Disk) {
  if (-not (Test-Path -LiteralPath $Disk)) { throw "Disk image not found: $Disk" }
  $args += @("-drive", "file=$Disk,if=virtio,format=qcow2")
}

if ($Iso) {
  if (-not (Test-Path -LiteralPath $Iso)) { throw "ISO not found: $Iso" }
  $args += @("-cdrom", $Iso, "-boot", "d")
}

if ($ScreenshotDir) {
  New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
  Write-Output "Guest acceptance screenshots should be copied to $ScreenshotDir after the run."
}

Write-Output "Starting QEMU with $Accel. Close the guest from inside the session when idle."
& $qemu @args
