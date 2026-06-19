#!/usr/bin/env python3

"""Update Semaphore and Kubespray versions in an env file."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Component:
    name: str
    env_key: str
    releases_url: str
    strip_leading_v: bool


COMPONENTS = (
    Component(
        name="Semaphore",
        env_key="SEMAPHORE_VERSION",
        releases_url="https://api.github.com/repos/semaphoreui/semaphore/releases?per_page=30",
        strip_leading_v=True,
    ),
    Component(
        name="Kubespray",
        env_key="KUBESPRAY_REF",
        releases_url="https://api.github.com/repos/kubernetes-sigs/kubespray/releases?per_page=30",
        strip_leading_v=False,
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Update SEMAPHORE_VERSION and KUBESPRAY_REF to the latest stable "
            "non-draft, non-prerelease GitHub releases."
        )
    )
    parser.add_argument("env_path", nargs="?", default=".env", help="Path to the env file")
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Report stable releases without modifying the env file",
    )
    return parser.parse_args()


def github_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "semaphore-kubespray-version-checker",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def latest_stable_version(component: Component) -> str:
    request = urllib.request.Request(component.releases_url, headers=github_headers())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            releases = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"could not fetch {component.name} releases: {exc}") from exc

    if not isinstance(releases, list):
        raise RuntimeError(f"unexpected response from the {component.name} releases API")

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = str(release.get("tag_name", "")).strip()
        if not tag:
            continue
        if component.strip_leading_v and tag.startswith("v"):
            return tag[1:]
        return tag

    raise RuntimeError(f"no stable {component.name} release was found")


def pattern_for(key: str) -> re.Pattern[str]:
    return re.compile(rf"^({re.escape(key)}=)[^ #]*(.*)$", re.MULTILINE)


def current_value(contents: str, key: str) -> str | None:
    match = pattern_for(key).search(contents)
    if not match:
        return None
    line = match.group(0)
    value = line.split("=", 1)[1].split("#", 1)[0].strip()
    return value or None


def replace_or_append(contents: str, key: str, value: str) -> str:
    pattern = pattern_for(key)
    if pattern.search(contents):
        return pattern.sub(rf"\g<1>{value}\g<2>", contents)
    separator = "" if not contents or contents.endswith("\n") else "\n"
    return f"{contents}{separator}{key}={value} # set by update script\n"


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

    contents = env_path.read_text(encoding="utf-8")
    latest_values: dict[str, str] = {}
    changed_components: list[str] = []

    try:
        for component in COMPONENTS:
            latest = latest_stable_version(component)
            current = current_value(contents, component.env_key)
            latest_values[component.env_key] = latest
            print(f"Current {component.name} version: {current or 'not set'}")
            print(f"Latest stable {component.name} version: {latest}")
            if current != latest:
                changed_components.append(component.name)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if not changed_components:
        print("Semaphore and Kubespray are already at their latest stable releases.")
        return 0

    print(f"Stable updates available: {', '.join(changed_components)}")
    if args.check_only:
        return 0

    backup_path = env_path.with_name(f"{env_path.name}.bak")
    backup_path.write_text(contents, encoding="utf-8")

    updated = contents
    for component in COMPONENTS:
        updated = replace_or_append(
            updated,
            component.env_key,
            latest_values[component.env_key],
        )

    atomic_write(env_path, updated)
    print(f"Updated {env_path}; previous contents saved to {backup_path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
