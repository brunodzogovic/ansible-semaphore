#!/usr/bin/env python3

"""Update SEMAPHORE_VERSION in an env file to the latest stable release."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

RELEASES_URL = "https://api.github.com/repos/semaphoreui/semaphore/releases?per_page=30"
VERSION_PATTERN = re.compile(r"^(SEMAPHORE_VERSION=)[^ #]*(.*)$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update SEMAPHORE_VERSION to the latest non-draft, non-prerelease Semaphore release."
    )
    parser.add_argument("env_path", nargs="?", default=".env", help="Path to the env file")
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Report the latest stable version without modifying the env file",
    )
    return parser.parse_args()


def latest_stable_version() -> str:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "semaphore-kubespray-version-checker",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(RELEASES_URL, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            releases = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"could not fetch Semaphore releases: {exc}") from exc

    if not isinstance(releases, list):
        raise RuntimeError("unexpected response from the GitHub releases API")

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = str(release.get("tag_name", "")).strip()
        if not tag:
            continue
        return tag[1:] if tag.startswith("v") else tag

    raise RuntimeError("no stable Semaphore release was found")


def current_version(contents: str) -> str | None:
    match = VERSION_PATTERN.search(contents)
    if not match:
        return None
    line = match.group(0)
    value = line.split("=", 1)[1].split("#", 1)[0].strip()
    return value or None


def atomic_write(path: Path, contents: str) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as temporary:
        temporary.write(contents)
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def main() -> int:
    args = parse_args()
    env_path = Path(args.env_path)
    if not env_path.is_file():
        print(f"Error: {env_path} not found", file=sys.stderr)
        return 1

    try:
        latest = latest_stable_version()
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    contents = env_path.read_text(encoding="utf-8")
    current = current_version(contents)

    print(f"Current Semaphore version: {current or 'not set'}")
    print(f"Latest stable Semaphore version: {latest}")

    if current == latest:
        print("Semaphore is already at the latest stable release.")
        return 0

    if args.check_only:
        print("A stable Semaphore update is available.")
        return 0

    backup_path = env_path.with_name(f"{env_path.name}.bak")
    backup_path.write_text(contents, encoding="utf-8")

    if VERSION_PATTERN.search(contents):
        updated = VERSION_PATTERN.sub(rf"\g<1>{latest}\g<2>", contents)
    else:
        separator = "" if not contents or contents.endswith("\n") else "\n"
        updated = f"{contents}{separator}SEMAPHORE_VERSION={latest} # set by update script\n"

    atomic_write(env_path, updated)
    print(f"Updated {env_path}; previous contents saved to {backup_path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
