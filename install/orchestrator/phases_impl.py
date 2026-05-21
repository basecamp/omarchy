"""Concrete phase implementations.

Each function takes the InstallContext and either returns or raises. Phases are
small wrappers — heavy lifting lives in archinstall_adapter (for Arch substrate
work) and helpers.* (for Omarchy-specific work).

Most are stubbed until Chunks 2–6 land. Keeping them here so the phase wiring
in main.py is testable end-to-end as a smoke check ('every phase imports
cleanly') from Chunk 1 onwards.
"""

from __future__ import annotations

from . import archinstall_adapter as arch
from .context import InstallContext


def prepare_live(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def cleanup_disk(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def partition_and_mount(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def install_base(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def install_bootloader(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def write_limine_config(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 3")


def install_early_omarchy_packages(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 4")


def create_user(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 2")


def install_omarchy_runtime(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 4")


def run_chroot_finalizer(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 5")


def validate_boot(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 6")


def finish(ctx: InstallContext) -> None:
    raise NotImplementedError("Chunk 6")
