"""Install context: parsed configurator output, invocation paths, and a
mutable `state` dict for objects that live across phases (e.g., the
archinstall config handler and mirror list handler)."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class InstallContext:
    config_path: Path
    creds_path: Path
    full_name: str
    email: str
    encrypt: bool

    user_configuration: dict
    user_credentials: dict

    target: Path = Path("/mnt")
    omarchy_path: Path = Path("/usr/share/omarchy")
    state_dir: Path = Path("/run/omarchy-install")
    log_path: Path = Path("/var/log/omarchy-install.log")
    target_log_path: Path = Path("/mnt/var/log/omarchy-install.log")

    # Mutable per-run state shared across phases (e.g., 'arch_config_handler',
    # 'mirror_handler'). Phases populate as needed; later phases read.
    state: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_args(cls, args) -> "InstallContext":
        config_path = Path(args.config)
        creds_path = Path(args.creds)
        return cls(
            config_path=config_path,
            creds_path=creds_path,
            full_name=_read_text(args.full_name_file),
            email=_read_text(args.email_file),
            encrypt=_read_text(args.encrypt_file).lower() in ("true", "yes", "1"),
            user_configuration=json.loads(config_path.read_text()),
            user_credentials=json.loads(creds_path.read_text()),
        )

    @property
    def username(self) -> str:
        return self.user_credentials["users"][0]["username"]


def _read_text(path: str | None) -> str:
    if not path:
        return ""
    p = Path(path)
    if not p.exists():
        return ""
    return p.read_text().strip()
