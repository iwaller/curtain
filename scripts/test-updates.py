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

signer = ROOT / 'scripts/update-signing.sh'
test_secret = OUT / 'keys/test.private-key'
test_public = OUT / 'test-public.txt'
subprocess.run([str(signer), 'generate', str(test_secret), str(test_public)], check=True)
assert stat.S_IMODE(test_secret.stat().st_mode) == 0o600
assert stat.S_IMODE(test_secret.parent.stat().st_mode) == 0o700
original_secret = test_secret.read_bytes()
assert subprocess.run([str(signer), 'generate', str(test_secret), str(test_public)], capture_output=True).returncode != 0
assert test_secret.read_bytes() == original_secret
public_key = test_public.read_text().strip()
print('PASS key generation permissions and refusal to overwrite existing keys', flush=True)

def fixture(name, changes=None, adhoc=False, missing_helper=False, missing_renderer=False):
    app = OUT / name / 'Curtain.app'
    shutil.copytree(APP, app)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleShortVersionString'] = '0.2.0'
    info['CurtainUpdatePublicKey'] = public_key
    info.update(changes or {})
    plist.write_bytes(plistlib.dumps(info))
    helper = app / 'Contents/Helpers/CurtainWatchdog'
    if missing_helper:
        helper.unlink()
    elif adhoc:
        subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', '-', str(helper)], check=True, capture_output=True)
    renderer = app / "Contents/Helpers/CurtainRenderer"
    if missing_renderer:
        renderer.unlink()
    elif adhoc:
        subprocess.run(["codesign", "--force", "--timestamp=none", "--sign", "-", str(renderer)], check=True, capture_output=True)
    subprocess.run(['codesign', '--force', '--timestamp=none', '--sign', '-' if adhoc else identity,
                    '--identifier', 'local.zjf.curtain', str(app)], check=True, capture_output=True)
    return app

valid = fixture('valid')
fixture('wrong-id', {'CFBundleIdentifier': 'local.other.app'})
fixture('incompatible', {'LSMinimumSystemVersion': '999.0'})
fixture('missing-helper', missing_helper=True)
fixture('missing-renderer', missing_renderer=True)
tampered_renderer = fixture('tampered-renderer') / 'Contents/Helpers/CurtainRenderer'
with tampered_renderer.open('ab') as stream:
    stream.write(b'tampering')
adhoc = fixture('adhoc', adhoc=True)
fixture('wrong-key', {'CurtainUpdatePublicKey': 'not-the-pinned-key'}, adhoc=True)
tampered = fixture('tampered')
(tampered / 'Contents/Info.plist').write_bytes(b'not a plist')
tampered_helper = fixture('tampered-helper') / 'Contents/Helpers/CurtainWatchdog'
with tampered_helper.open('ab') as stream:
    stream.write(b'tampering')
subprocess.run(['/usr/bin/tar', '--format', 'zip', '-cf', str(OUT / 'valid.zip'), '-C', str(valid.parent), 'Curtain.app'], check=True)
subprocess.run(['/usr/bin/tar', '--format', 'zip', '-cf', str(OUT / 'adhoc.zip'), '-C', str(adhoc.parent), 'Curtain.app'], check=True)
for name in ('valid', 'adhoc'):
    subprocess.run([str(signer), 'sign', str(test_secret), str(OUT / f'{name}.zip')], check=True)
subprocess.run([str(signer), 'generate', str(OUT / 'keys/wrong.private-key'), str(OUT / 'wrong-public.txt')], check=True)
assert subprocess.run([str(signer), 'sign', str(OUT / 'keys/wrong.private-key'), str(OUT / 'valid.zip')], capture_output=True).returncode != 0
print('PASS release signer rejects a private key that differs from the embedded public key', flush=True)
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
subprocess.run(['xcrun', 'swiftc', '-Osize', '-whole-module-optimization', '-module-cache-path', str(ROOT / 'build/module-cache'), '-framework', 'AppKit',
                '-framework', 'Security', 'Sources/App/AppVersion.swift', 'Sources/App/UpdatePackage.swift',
                'build/UpdateTrust.swift',
                'Sources/App/Updater.swift', 'Sources/App/PermissionGuide.swift', 'Tests/UpdateTests.swift',
                '-o', str(binary)], cwd=ROOT, check=True)
subprocess.run([str(binary), str(OUT), str(APP)], cwd=ROOT, check=True, timeout=90)
