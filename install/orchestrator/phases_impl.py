"""Concrete phase implementations.

Phase ordering:

    prepare_live          → live ISO env + load arch config
    arch_install          → archinstall-driven install (partition, base,
                            bootloader, write limine config, early omarchy
                            pkgs, useradd, runtime omarchy pkgs)
    run_chroot_finalizer  → arch-chroot finalize.sh as the install user
    validate_boot         → assert UKI / limine.conf / kernel cmdline are sane
    finish                → reboot prompt

Heavy lifting in arch_install lives in archinstall_adapter (for the Installer
context manager) and in this file (for our limine-config write + omarchy
package selection). Other phases are kept small.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from . import archinstall_adapter as arch
from .context import InstallContext
from .ui import info


# Packages installed BEFORE useradd. omarchy-settings populates /etc/skel so
# the user's home gets seeded correctly; omarchy-installer ships the install/
# tree + finalize.sh that the in-chroot finalizer needs.
EARLY_PACKAGES = [
    "base-devel",
    "git",
    "omarchy-keyring",
    "omarchy-settings",
    "omarchy-installer",
]


# ─────────────────────────────────────────────────────────────────────────────
# prepare_live: parse user_configuration.json/user_credentials.json, build the
# archinstall handlers. Cached on ctx.state for downstream phases.
# ─────────────────────────────────────────────────────────────────────────────

def prepare_live(ctx: InstallContext) -> None:
    ctx.state["arch_config_handler"] = arch.load_arch_config(
        ctx.config_path, ctx.creds_path
    )
    ctx.state["mirror_handler"] = arch.make_mirror_handler(offline=True)


# ─────────────────────────────────────────────────────────────────────────────
# arch_install: everything inside a single Installer context manager. Mirrors
# guided.py's perform_installation() but reorders so our limine config write
# lands between add_bootloader and the first add_additional_packages call, and
# user creation happens AFTER early omarchy packages populate /etc/skel.
# ─────────────────────────────────────────────────────────────────────────────

def arch_install(ctx: InstallContext) -> None:
    handler = ctx.state["arch_config_handler"]
    mirror_handler = ctx.state["mirror_handler"]
    config = handler.config

    info("› partitioning + formatting + encrypting")
    arch.perform_filesystem_operations(config)

    info("› opening installer context")
    with arch.open_installer(config, ctx.target, silent=True) as installer:
        if not arch.is_pre_mount(config):
            installer.mount_ordered_layout()

        installer.sanity_check(
            offline=True,
            skip_ntp=True,
            skip_wkd=True,
        )

        if not arch.is_pre_mount(config) and arch.is_encrypted(config):
            installer.generate_key_files()

        if config.mirror_config:
            installer.set_mirrors(mirror_handler, config.mirror_config, on_target=False)

        info("› installing base system")
        installer.minimal_installation(
            optional_repositories=(
                config.mirror_config.optional_repositories
                if config.mirror_config else []
            ),
            mkinitcpio=True,
            hostname=config.hostname,
            locale_config=config.locale_config,
            pacman_config=config.pacman_config,
        )

        if config.mirror_config:
            installer.set_mirrors(mirror_handler, config.mirror_config, on_target=True)

        if config.swap and config.swap.enabled:
            installer.setup_swap(algo=config.swap.algorithm)

        info("› installing bootloader (Limine)")
        if config.bootloader_config:
            installer.add_bootloader(
                config.bootloader_config.bootloader,
                config.bootloader_config.uki,
                config.bootloader_config.removable,
            )

        info("› writing Limine config (so limine-mkinitcpio-hook fires correctly)")
        _write_limine_defaults(ctx)

        info(f"› installing early Omarchy packages: {', '.join(EARLY_PACKAGES)}")
        installer.add_additional_packages(EARLY_PACKAGES)

        info("› creating user (with /etc/skel populated)")
        if config.auth_config and config.auth_config.users:
            installer.create_users(config.auth_config.users)

        info("› installing Omarchy runtime + omarchy-base.packages")
        runtime_pkgs = _runtime_package_list(ctx)
        installer.add_additional_packages(runtime_pkgs)

        # Standard arch finishers.
        if config.timezone:
            installer.set_timezone(config.timezone)
        if config.ntp:
            installer.activate_time_synchronization()
        if root := arch.root_user(config):
            installer.set_user_password(root)

        installer.genfstab()


# ─────────────────────────────────────────────────────────────────────────────
# Limine config write — extracted from install/login/limine-snapper.sh logic.
# Reads cmdline from /mnt/boot/limine.conf (which add_bootloader wrote),
# substitutes @@CMDLINE@@ into the template, writes /etc/default/limine +
# /etc/kernel/cmdline.
# ─────────────────────────────────────────────────────────────────────────────

def _write_limine_defaults(ctx: InstallContext) -> None:
    if not arch.is_limine(ctx.state["arch_config_handler"].config):
        return

    limine_conf = ctx.target / "boot" / "limine.conf"
    if not limine_conf.exists():
        raise RuntimeError(f"{limine_conf} not found after add_bootloader")

    cmdline = _extract_cmdline(limine_conf)
    if not cmdline.strip():
        raise RuntimeError("Could not extract kernel cmdline from limine.conf")
    if "root=" not in cmdline:
        raise RuntimeError(f"Extracted cmdline has no root=: {cmdline!r}")

    # The template lives in omarchy-installer (this package), so it's
    # available from /mnt/usr/share/omarchy/... as soon as the early
    # omarchy-installer pacstrap completes — but we want it BEFORE that.
    # Read from our own runtime tree on the live ISO instead.
    template = ctx.omarchy_path / "install" / "assets" / "limine" / "default.conf"
    if not template.exists():
        # Fallback to the legacy path while we migrate templates between packages.
        template = ctx.omarchy_path / "default" / "limine" / "default.conf"
    if not template.exists():
        raise RuntimeError(f"Limine template not found at {template}")

    default_limine = ctx.target / "etc" / "default" / "limine"
    default_limine.parent.mkdir(parents=True, exist_ok=True)
    default_limine.write_text(template.read_text().replace("@@CMDLINE@@", cmdline))

    kernel_cmdline = ctx.target / "etc" / "kernel" / "cmdline"
    kernel_cmdline.parent.mkdir(parents=True, exist_ok=True)
    kernel_cmdline.write_text(cmdline + "\n")


def _extract_cmdline(limine_conf: Path) -> str:
    for line in limine_conf.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("cmdline:"):
            return stripped[len("cmdline:"):].strip()
    return ""


def _runtime_package_list(ctx: InstallContext) -> list[str]:
    """omarchy + every package in install/omarchy-base.packages that isn't
    already in EARLY_PACKAGES."""
    base_pkgs_file = ctx.omarchy_path / "install" / "omarchy-base.packages"
    pkgs = ["omarchy"]
    early = set(EARLY_PACKAGES)
    for raw in base_pkgs_file.read_text().splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if s not in early and s not in pkgs:
            pkgs.append(s)
    return pkgs


# ─────────────────────────────────────────────────────────────────────────────
# run_chroot_finalizer: arch-chroot -u $user into /mnt and run finalize.sh.
# Inherits stdout/stderr so the in-target output streams to our log capture.
# ─────────────────────────────────────────────────────────────────────────────

def run_chroot_finalizer(ctx: InstallContext) -> None:
    env_extras = [
        f"OMARCHY_INSTALL_MODE=offline",
        f"OMARCHY_USER_NAME={ctx.full_name}",
        f"OMARCHY_USER_EMAIL={ctx.email}",
        f"USER={ctx.username}",
        f"HOME=/home/{ctx.username}",
    ]
    cmd = [
        "arch-chroot",
        "-u", ctx.username,
        str(ctx.target),
        "env", "--unset=XDG_RUNTIME_DIR",
        *env_extras,
        "/bin/bash", "-lc",
        f"bash {ctx.omarchy_path}/finalize.sh",
    ]
    subprocess.run(cmd, check=True)


# ─────────────────────────────────────────────────────────────────────────────
# validate_boot: hard checks before reboot. If the install ran but produced
# a UKI that can't actually boot, we want to halt here, not surprise the user.
# ─────────────────────────────────────────────────────────────────────────────

def validate_boot(ctx: InstallContext) -> None:
    limine_conf = ctx.target / "boot" / "limine.conf"
    if not limine_conf.exists():
        raise RuntimeError(f"{limine_conf} missing")

    content = limine_conf.read_text()
    if "^/+Omarchy" not in content and "Omarchy" not in content:
        raise RuntimeError("/boot/limine.conf has no Omarchy entry")

    if ctx.encrypt and "cryptdevice=" not in content:
        raise RuntimeError("Encrypted install but /boot/limine.conf has no cryptdevice=")

    kernel_cmdline = ctx.target / "etc" / "kernel" / "cmdline"
    if not kernel_cmdline.exists():
        raise RuntimeError(f"{kernel_cmdline} missing — UKI would have no cmdline")

    uki_dir = ctx.target / "boot" / "EFI" / "Linux"
    if uki_dir.exists():
        ukis = list(uki_dir.glob("*_linux*.efi"))
        if not ukis:
            raise RuntimeError(f"No UKI found in {uki_dir}")


# ─────────────────────────────────────────────────────────────────────────────
# finish: show completion + offer reboot. No mutation.
# ─────────────────────────────────────────────────────────────────────────────

def finish(ctx: InstallContext) -> None:
    from .ui import confirm
    info("Installation finished. Reboot when ready.")
    if confirm("Reboot now?", default=True):
        os.system("reboot")
