#!/usr/bin/env python3
"""Fetch optional third-party artwork from its pinned source, verifying every file."""
import hashlib
import json
import re
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent.parent / "Assets/HeroIcons"
REVISION = "f4ddc06cf07d0741c40beda77eeeb1a81a99a279"
SOURCE = "https://github.com/drippinghere/overwatch-hero-icons"


def fetch(hero):
    name, digest = hero["id"], hero["sha256"]
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Invalid artwork manifest entry")
    target = DIRECTORY / "2d" / f"{name}.png"
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == digest:
        return
    address = f"https://raw.githubusercontent.com/drippinghere/overwatch-hero-icons/{REVISION}/2d/{name}.png"
    request = urllib.request.Request(address, headers={"User-Agent": "OverLaunch-source-build"})
    with urllib.request.urlopen(request, timeout=45) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError(f"Artwork checksum mismatch: {name}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=f".{name}-", suffix=".partial", delete=False) as file:
            temporary = Path(file.name)
            file.write(data)
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    catalog = json.loads((DIRECTORY / "catalog.json").read_text())
    if catalog["sourceURL"] != SOURCE or catalog["sourceRevision"] != REVISION:
        raise ValueError("Unexpected artwork source")
    heroes = catalog["heroes"]
    if len({hero["id"] for hero in heroes}) != len(heroes):
        raise ValueError("Duplicate artwork IDs")
    (DIRECTORY / "2d").mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, heroes))
    print(f"Ready: {len(heroes)} verified hero portraits (third-party artwork, see THIRD_PARTY.md)")


if __name__ == "__main__":
    main()
