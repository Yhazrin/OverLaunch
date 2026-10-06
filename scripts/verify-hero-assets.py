#!/usr/bin/env python3
"""Check bundled artwork against the pinned source manifest; never downloads."""
import hashlib
import json
import re
from pathlib import Path

directory = Path(__file__).resolve().parent.parent / "Assets/HeroIcons"
catalog = json.loads((directory / "catalog.json").read_text())
seen = set()
for hero in catalog["heroes"]:
    name = hero["id"]
    assert re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name), name
    assert name not in seen, name
    seen.add(name)
    file = directory / "2d" / f"{name}.png"
    assert hashlib.sha256(file.read_bytes()).hexdigest() == hero["sha256"], name
assert seen == {f.stem for f in (directory / "2d").glob("*.png")}
print(f"Verified {len(seen)} bundled hero icons")
