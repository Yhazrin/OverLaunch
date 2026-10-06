from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent / 'Assets/Fonts'
manifest = json.loads((root / 'manifest.json').read_text())
for name, expected in manifest['files'].items():
    if Path(name).name != name:
        raise SystemExit('Invalid font asset path')
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit(f'Font asset checksum mismatch: {name}')
if 'SIL OPEN FONT LICENSE Version 1.1' not in (root / 'OFL.txt').read_text():
    raise SystemExit('Font license missing')
print('Verified bundled Smiley Sans 2.0.1')
