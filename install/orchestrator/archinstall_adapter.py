"""Thin compatibility wall around the archinstall Python library.

ONLY this module imports from archinstall. Everything else uses these helpers.
If archinstall's API churns, the blast radius is contained here.

Tested against archinstall 4.3 (Python 3.14).

The canonical call sequence (mirrored from archinstall.scripts.guided.py) is:

    FilesystemHandler(disk_config).perform_filesystem_operations()
    with Installer(mountpoint, disk_config, kernels=, silent=) as inst:
        inst.mount_ordered_layout()
        inst.sanity_check(offline=, skip_ntp=, skip_wkd=)
        inst.generate_key_files()                     # encrypted only
        inst.set_mirrors(handler, mirror_config, on_target=False)
        inst.minimal_installation(...)                # base + linux pacstrap
        inst.set_mirrors(handler, mirror_config, on_target=True)
        inst.setup_swap(algo=...)
        inst.add_bootloader(bootloader, uki, removable)
        inst.create_users(users)
        inst.add_additional_packages(packages)
        inst.set_timezone(tz)
        inst.activate_time_synchronization()
        inst.set_user_password(root_user)
        inst.enable_service(services)
        inst.genfstab()

Our orchestrator interleaves `write_limine_config` between `add_bootloader`
and the first `add_additional_packages` so the limine UKI hook fires once,
correctly, on its first install.
"""

from __future__ import annotations

import os
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

# Imports are top-level so a missing/incompatible archinstall surfaces at
# orchestrator startup, not deep inside a phase.
from archinstall.lib.args import ArchConfig, ArchConfigHandler
from archinstall.lib.authentication.authentication_handler import AuthenticationHandler
from archinstall.lib.configuration import ConfigurationOutput
from archinstall.lib.disk.filesystem import FilesystemHandler
from archinstall.lib.installer import Installer
from archinstall.lib.mirror.mirror_handler import MirrorListHandler
from archinstall.lib.models import Bootloader
from archinstall.lib.models.device import DiskLayoutType, EncryptionType
from archinstall.lib.models.users import User


def load_arch_config(config_path: Path, creds_path: Path) -> ArchConfigHandler:
    """Build an ArchConfigHandler from on-disk JSON. archinstall reads the
    paths via env vars, so we set them before instantiating the handler."""
    os.environ["ARCHINSTALL_CONFIG"] = str(config_path)
    os.environ["ARCHINSTALL_CREDS"] = str(creds_path)
    return ArchConfigHandler()


def make_mirror_handler(offline: bool = True) -> MirrorListHandler:
    return MirrorListHandler(offline=offline, verbose=False)


def perform_filesystem_operations(arch_config: ArchConfig) -> None:
    """Partition, format, encrypt. archinstall's FilesystemHandler is its own
    object (separate from Installer) so we run it before opening the
    Installer context manager."""
    if not arch_config.disk_config:
        raise RuntimeError("disk_config missing from arch config")
    FilesystemHandler(arch_config.disk_config).perform_filesystem_operations()


@contextmanager
def open_installer(
    arch_config: ArchConfig,
    mountpoint: Path,
    silent: bool = True,
) -> Iterator[Installer]:
    """Yield an open Installer; ensures __exit__ runs even on exception so
    /mnt is left clean for a retry."""
    if not arch_config.disk_config:
        raise RuntimeError("disk_config missing from arch config")
    with Installer(
        str(mountpoint),
        arch_config.disk_config,
        kernels=arch_config.kernels,
        silent=silent,
    ) as installer:
        yield installer


def is_encrypted(arch_config: ArchConfig) -> bool:
    disk = arch_config.disk_config
    if not disk or not disk.disk_encryption:
        return False
    return disk.disk_encryption.encryption_type != EncryptionType.NO_ENCRYPTION


def is_pre_mount(arch_config: ArchConfig) -> bool:
    return bool(
        arch_config.disk_config
        and arch_config.disk_config.config_type == DiskLayoutType.Pre_mount
    )


def is_limine(arch_config: ArchConfig) -> bool:
    bl = arch_config.bootloader_config
    return bool(bl and bl.bootloader == Bootloader.Limine)


def root_user(arch_config: ArchConfig) -> User | None:
    auth = arch_config.auth_config
    if not auth or not auth.root_enc_password:
        return None
    return User("root", auth.root_enc_password, False)
