#!/usr/bin/env python3
"""Prepare the optional free runtime. Run only after stopping OW120's Wine processes."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import urllib.request

PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path.home() / 'Library/Application Support/OW120'
COMMUNITY = ROOT / 'Community'
ASSETS = [
    ('soju-engine-v1.5.tar.xz', 'https://github.com/BCD1210/soju/releases/download/engine-v1.5/wine-engine-x86_64.tar.xz', '7b96a4407308493ae92bebe96039bbc8d0bf3b86c22cb99c782f73cf7be3738e', 'soju26'),
    ('dxmt-ow2-pack-v0.2.tar.gz', 'https://github.com/NerRobDog/dxmt/releases/download/v0.80-ow2-0.2/dxmt-ow2-pack-v0.2.tar.gz', '8d4e778ff9868883a064d7b9bfb372ed6e286e4233f60c053075ca983b2bc256', 'graphics'),
]

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def main():
    processes = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True)
    if any(str(ROOT / part) in processes for part in ['Community/', 'Runtime/']):
        raise RuntimeError('请先在 OW120 停止游戏与战网，再准备社区引擎。')
    if not (ROOT / 'installation.json').exists():
        raise RuntimeError('此迁移工具要求先完成 OW120 原有隔离环境准备。')
    COMMUNITY.mkdir(parents=True, exist_ok=True)
    vendor = PROJECT / 'Vendor'
    vendor.mkdir(exist_ok=True)
    for name, url, digest, destination in ASSETS:
        archive = vendor / name
        if not archive.exists():
            partial = archive.with_suffix(archive.suffix + '.partial')
            print('下载', name, flush=True)
            urllib.request.urlretrieve(url, partial)
            if hashlib.sha256(partial.read_bytes()).hexdigest() != digest:
                raise RuntimeError('下载校验失败：' + name)
            partial.rename(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
            raise RuntimeError('归档校验失败：' + name)
        target = COMMUNITY / destination
        expected = target / ('bin/wine' if destination == 'soju26' else 'dxmt-ow2-pack')
        if not expected.exists():
            with tarfile.open(archive) as tar:
                for member in tar:
                    path = PurePosixPath(member.name)
                    if path.is_absolute() or '..' in path.parts:
                        raise RuntimeError('归档路径无效')
            target.mkdir(parents=True, exist_ok=True)
            run('/usr/bin/tar', '-xf', archive, '-C', target)
    # APFS copy-on-write copies; never hard link settings, registries or game files.
    for source, target in [(ROOT / 'Bottles/ow120', COMMUNITY / 'prefix-soju26'), (ROOT / 'Documents', COMMUNITY / 'Documents-soju26')]:
        if not target.exists():
            run('/bin/cp', '-cR', source, target)
    documents = COMMUNITY / 'prefix-soju26/drive_c/users/crossover/Documents'
    if documents.is_symlink():
        documents.unlink()
    elif documents.exists():
        raise RuntimeError('Documents 是实体目录；为避免覆盖数据，请先人工检查。')
    documents.symlink_to(COMMUNITY / 'Documents-soju26', target_is_directory=True)
    for name in ['profile.json', 'dxmt.conf']:
        if not (COMMUNITY / name).exists():
            shutil.copy2(ROOT / name, COMMUNITY / name)
    engine = COMMUNITY / 'soju26'
    metal = COMMUNITY / 'graphics/dxmt-ow2-pack/x86_64-unix/winemetal.so'
    run('/usr/bin/codesign', '--force', '--sign', '-', metal)
    for binary in [engine / 'bin/wine', engine / 'bin/wineserver', metal]:
        run('/usr/bin/codesign', '--verify', '--strict', binary)
    # Agent-spawned games do not reliably inherit the loader-path environment.
    # Install built-in DXMT in the standard 64-bit paths, preserving 32-bit CEF.
    pack = COMMUNITY / 'graphics/dxmt-ow2-pack'
    backup = COMMUNITY / 'GraphicsBackups/soju26-before-dxmt'
    files = [(pack / 'x86_64-windows' / n, engine / 'lib/wine/x86_64-windows' / n, 'engine/' + n)
             for n in ['d3d11.dll', 'dxgi.dll', 'd3d10core.dll', 'winemetal.dll']]
    files += [(metal, engine / 'lib/wine/x86_64-unix/winemetal.so', 'engine/winemetal.so'),
              (pack / 'x86_64-windows/winemetal.dll', COMMUNITY / 'prefix-soju26/drive_c/windows/system32/winemetal.dll', 'prefix/winemetal.dll')]
    for source, target, key in files:
        if target.exists() and source.read_bytes() == target.read_bytes():
            continue
        saved = backup / key
        if target.exists() and not saved.exists():
            saved.parent.mkdir(parents=True, exist_ok=True)
            run('/bin/cp', '-c', target, saved)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + '.ow120-new')
        shutil.copy2(source, temporary)
        temporary.replace(target)
    run('/usr/bin/codesign', '--verify', '--strict', engine / 'lib/wine/x86_64-unix/winemetal.so')
    env = {k: v for k, v in os.environ.items() if not k.startswith(('WINE', 'CX_', 'DYLD_', 'DXMT_', 'MTL_'))}
    env.update(WINEPREFIX=str(COMMUNITY / 'prefix-soju26'), WINEDEBUG='-all', WINEMSYNC='1', WINEESYNC='0',
               DYLD_FALLBACK_LIBRARY_PATH=str(engine / 'lib') + ':/usr/lib:/usr/libexec:/usr/lib/system',
               ROSETTA_ADVERTISE_AVX='1',
               WINE_SIMULATE_WRITECOPY='1',
               WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree,mshtml=')
    try:
        result = run(engine / 'bin/wine', 'cmd.exe', '/c', 'echo OW120_COMMUNITY_OK', env=env, capture_output=True, text=True, timeout=90)
        if 'OW120_COMMUNITY_OK' not in result.stdout:
            raise RuntimeError('Windows 程序启动未通过，保留现有运行时选择。')
    finally:
        # A short smoke test can leave no running server; -k then returns 1.
        subprocess.run([str(engine / 'bin/wineserver'), '-k'], env=env, check=False)
        run(engine / 'bin/wineserver', '-w', env=env, timeout=20)
    (COMMUNITY / 'runtime-sources.json').write_text(json.dumps(ASSETS, indent=2))
    (ROOT / 'active-runtime').write_text('community-soju26\n')
    print('社区运行时 Windows 冒烟通过。现在从 OW120 启动战网；实战帧率需另行验证。')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit(str(error))
