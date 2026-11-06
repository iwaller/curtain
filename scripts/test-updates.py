#!/usr/bin/env python3
"""Isolated signed bundles and malicious archives. Never launches/replaces an installed app."""
from pathlib import Path
import io
import os
import plistlib
import shutil
import stat
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/update-tests'
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)
APP = ROOT / 'build/Curtain.app'
if not APP.exists():
    raise SystemExit('Run ./scripts/build.sh first')
identity = os.environ.get('CURTAIN_SIGN_IDENTITY')
if not identity:
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    identity = next((line.split('"')[1] for line in identities.splitlines() if 'Apple Development' in line), '-')

def fixture(name, changes=None, adhoc=False, missing_helper=False):
    app = OUT / name / 'Curtain.app'
    shutil.copytree(APP, app)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleShortVersionString'] = '0.2.0'
    info.update(changes or {})
    plist.write_bytes(plistlib.dumps(info))
    helper = app / 'Contents/Helpers/CurtainWatchdog'
    if missing_helper:
        helper.unlink()
    elif adhoc:
        subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', '-', str(helper)], check=True, capture_output=True)
    subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', '-' if adhoc else identity,
                    '--identifier', 'local.zjf.curtain', str(app)], check=True, capture_output=True)
    return app

valid = fixture('valid')
fixture('wrong-id', {'CFBundleIdentifier': 'local.other.app'})
fixture('incompatible', {'LSMinimumSystemVersion': '999.0'})
fixture('missing-helper', missing_helper=True)
fixture('adhoc', adhoc=True)
tampered = fixture('tampered')
(tampered / 'Contents/Info.plist').write_bytes(b'not a plist')
tampered_helper = fixture('tampered-helper') / 'Contents/Helpers/CurtainWatchdog'
with tampered_helper.open('ab') as stream:
    stream.write(b'tampering')
subprocess.run(['/usr/bin/tar', '--format', 'zip', '-cf', str(OUT / 'valid.zip'), '-C', str(valid.parent), 'Curtain.app'], check=True)
for name, entry in [('traversal', 'Curtain.app/../../escaped'), ('absolute', '/tmp/curtain-update-escaped'),
                    ('foreign-root', 'Other.app/file')]:
    with zipfile.ZipFile(OUT / f'{name}.zip', 'w') as archive:
        archive.writestr(entry, 'must not be written')
with zipfile.ZipFile(OUT / 'symlink.zip', 'w') as archive:
    entry = zipfile.ZipInfo('Curtain.app/link')
    entry.create_system = 3
    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(entry, '../../outside')
# Test libarchive handling of hard links too; file extension does not dictate archive format.
with tarfile.open(OUT / 'hardlink.zip', 'w') as archive:
    entry = tarfile.TarInfo('Curtain.app/link')
    entry.type = tarfile.LNKTYPE
    entry.linkname = '../../outside'
    archive.addfile(entry)

binary = OUT / 'update-tests'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / 'build/module-cache'), '-framework', 'AppKit',
                '-framework', 'Security', 'Sources/App/AppVersion.swift', 'Sources/App/UpdatePackage.swift',
                'Sources/App/Updater.swift', 'Sources/App/PermissionGuide.swift', 'Tests/UpdateTests.swift',
                '-o', str(binary)], cwd=ROOT, check=True)
subprocess.run([str(binary), str(OUT), str(APP)], cwd=ROOT, check=True, timeout=90)
