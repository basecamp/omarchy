"""Thin compatibility wall around the archinstall Python library.

ONLY this module imports from archinstall. Everything else uses these functions.
If archinstall's API churns, the blast radius is contained here.

Tested against archinstall 4.3 (Python 3.14).
"""

from __future__ import annotations

# Phase 2 will populate this module. For now we declare the contract so the
# rest of the orchestrator can be wired up against the eventual surface area.


def prepare_live() -> None:
    """pacman-key init/populate, mount checks, etc. Currently a no-op stub."""
    raise NotImplementedError("populated in Chunk 2")


def cleanup_disk() -> None:
    raise NotImplementedError("populated in Chunk 2")


def create_partitions_and_mounts(install_ctx) -> None:
    raise NotImplementedError("populated in Chunk 2")


def install_base_system(install_ctx) -> None:
    raise NotImplementedError("populated in Chunk 2")


def install_limine_bootloader(install_ctx) -> None:
    raise NotImplementedError("populated in Chunk 2")


def create_users(install_ctx) -> None:
    raise NotImplementedError("populated in Chunk 2")
