"""Omarchy install orchestrator.

Single tool that owns the full install phase ordering, with archinstall used as
a library subsystem (not as the top-level installer).

Usage (typically invoked by bin/omarchy-install on the live ISO):

    omarchy-install \\
        --config user_configuration.json \\
        --creds user_credentials.json \\
        --full-name-file user_full_name.txt \\
        --email-file user_email_address.txt \\
        --encrypt-file user_encrypt_installation.txt
"""

from __future__ import annotations

import argparse
import sys

from . import archinstall_adapter as arch
from .context import InstallContext
from .phases import PhaseError, run
from .ui import error, info


def build_phases():
    """Phase order. Each entry is (display name, callable taking InstallContext).

    The ordering is the whole point of this orchestrator: package-install
    hooks (limine-mkinitcpio-hook, in particular) and useradd happen at
    points where their prerequisites are guaranteed to be in place.
    """
    from .phases_impl import (
        prepare_live,
        arch_install,
        run_chroot_finalizer,
        validate_boot,
        finish,
    )

    return [
        ("Preparing live environment", prepare_live),
        ("Installing Arch + Omarchy",  arch_install),
        ("Finalizing in chroot",       run_chroot_finalizer),
        ("Validating boot setup",      validate_boot),
        ("Finishing",                  finish),
    ]


def parse_args(argv):
    p = argparse.ArgumentParser(prog="omarchy-install")
    p.add_argument("--config", required=True, help="archinstall user_configuration.json")
    p.add_argument("--creds", required=True, help="archinstall user_credentials.json")
    p.add_argument("--full-name-file", help="text file with the user's full name")
    p.add_argument("--email-file", help="text file with the user's email address")
    p.add_argument("--encrypt-file", help="text file holding 'true' if root encryption enabled")
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv or sys.argv[1:])
    ctx = InstallContext.from_args(args)

    info(f"Installing Omarchy for {ctx.username} → {ctx.target}")

    try:
        run(ctx, build_phases())
    except PhaseError:
        error("Installation halted.")
        return 1
    except KeyboardInterrupt:
        error("Installation interrupted.")
        return 130

    info("Installation complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
