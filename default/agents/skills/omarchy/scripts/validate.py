#!/usr/bin/python3

"""Validate the Omarchy end-user skill against its links and CLI metadata."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote


LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
COMMAND_RE = re.compile(r"(?<![-\w/])omarchy(?:\s+(?:--?[A-Za-z0-9_.:/<>-]+|[A-Za-z0-9_.:/<>-]+))+")
INLINE_CODE_RE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")


def heading_anchor(value: str) -> str:
    value = re.sub(r"[`*_~]", "", value.strip().lower())
    value = re.sub(r"[^\w\- ]", "", value)
    return re.sub(r"[\s-]+", "-", value).strip("-")


def anchors(path: Path) -> set[str]:
    return {
        heading_anchor(match.group(1))
        for line in path.read_text(encoding="utf-8").splitlines()
        if (match := re.match(r"^#{1,6}\s+(.+?)\s*$", line))
    }


def load_metadata(root: Path, metadata_path: Path | None) -> dict:
    if metadata_path:
        return json.loads(metadata_path.read_text(encoding="utf-8"))
    environment = os.environ.copy()
    environment["OMARCHY_PATH"] = str(root)
    result = subprocess.run(
        ["bash", str(root / "bin/omarchy"), "commands", "--json"],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    return json.loads(result.stdout)


def validate_links(markdown: Path, skill_dir: Path) -> list[str]:
    errors = []
    for raw in LINK_RE.findall(markdown.read_text(encoding="utf-8")):
        destination = raw.split(maxsplit=1)[0].strip("<>")
        if re.match(r"^[a-z][a-z0-9+.-]*:", destination) or destination.startswith("#"):
            continue
        path_text, _, fragment = destination.partition("#")
        target = (markdown.parent / unquote(path_text)).resolve()
        try:
            target.relative_to(skill_dir.resolve())
        except ValueError:
            errors.append(f"{markdown}: link escapes skill directory: {destination}")
            continue
        if not target.is_file():
            errors.append(f"{markdown}: missing link target: {destination}")
        elif fragment and unquote(fragment) not in anchors(target):
            errors.append(f"{markdown}: missing anchor: {destination}")
    return errors


def validate_commands(markdown: Path, routes: set[str]) -> list[str]:
    errors = []
    in_fence = False
    for line_number, line in enumerate(markdown.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        fragments = [line] if in_fence else INLINE_CODE_RE.findall(line)
        for fragment in fragments:
            if fragment.lstrip().startswith("#"):
                continue
            for match in COMMAND_RE.finditer(fragment):
                invocation = match.group(0).rstrip(".,:;)")
                words = invocation.split()
                if any("<" in word or ">" in word for word in words):
                    continue
                if not any(invocation == route or invocation.startswith(route + " ") for route in routes):
                    errors.append(f"{markdown}:{line_number}: unknown command route: {invocation}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    script = Path(__file__).resolve()
    parser.add_argument("--root", type=Path, default=script.parents[5])
    parser.add_argument("--skill-dir", type=Path, default=script.parent.parent)
    parser.add_argument("--commands-json", type=Path)
    args = parser.parse_args()

    metadata = load_metadata(args.root.resolve(), args.commands_json)
    if not metadata.get("ok"):
        print("CLI metadata reports errors", file=sys.stderr)
        return 1
    routes = {
        route
        for command in metadata.get("commands", [])
        for route in command.get("routes", [command.get("route")])
        if route
    }
    routes.update({"omarchy --help", "omarchy commands"})
    routes.update(
        f"omarchy {command['group']}"
        for command in metadata.get("commands", [])
        if command.get("group")
    )

    markdown_files = sorted(args.skill_dir.glob("*.md"))
    errors = []
    for markdown in markdown_files:
        errors.extend(validate_links(markdown, args.skill_dir))
        errors.extend(validate_commands(markdown, routes))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"ok - validated {len(markdown_files)} skill documents against {len(routes)} CLI routes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
