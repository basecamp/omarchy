"""Thin gum wrapper so the orchestrator keeps the same terminal UX as the
existing bash installer."""

from __future__ import annotations

import subprocess


def style(text: str, *, foreground: str | None = None, padding: str | None = None) -> None:
    cmd = ["gum", "style"]
    if foreground:
        cmd += ["--foreground", foreground]
    if padding:
        cmd += ["--padding", padding]
    cmd.append(text)
    subprocess.run(cmd, check=False)


def confirm(prompt: str, *, default: bool = True) -> bool:
    cmd = ["gum", "confirm", "--default" if default else "--no-default", prompt]
    return subprocess.run(cmd).returncode == 0


def info(text: str) -> None:
    style(text, foreground="3", padding="1 0 0 4")


def error(text: str) -> None:
    style(text, foreground="1", padding="1 0 0 4")
