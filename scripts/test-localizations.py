#!/usr/bin/env python3
"""Test packaged native localizations in isolated processes; never launch the live controller."""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'build/Curtain.app'
OUT = ROOT / 'build/localization-tests'
if not APP.is_dir():
    raise SystemExit('Run ./scripts/build.sh first')
OUT.mkdir(parents=True, exist_ok=True)

def read_strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

english = read_strings(APP / 'Contents/Resources/en.lproj/Localizable.strings')
chinese = read_strings(APP / 'Contents/Resources/zh-Hans.lproj/Localizable.strings')
assert english.keys() == chinese.keys(), 'Language tables have different keys'
assert all(english.values()) and all(chinese.values()), 'Empty translation'
for key in english:
    assert english[key].count('%@') == chinese[key].count('%@'), f'Placeholder mismatch: {key}'
    for language in ('en', 'zh-Hans'):
        source = ROOT / f'Resources/{language}.lproj/Localizable.strings'
        packaged = APP / f'Contents/Resources/{language}.lproj/Localizable.strings'
        assert source.read_bytes() == packaged.read_bytes(), f'Stale packaged language: {language}'
with zipfile.ZipFile(ROOT / 'build/Curtain.zip') as archive:
    for language in ('en', 'zh-Hans'):
        member = f'Curtain.app/Contents/Resources/{language}.lproj/Localizable.strings'
        assert archive.read(member) == (APP / 'Contents/Resources' / f'{language}.lproj/Localizable.strings').read_bytes()
print(f'PASS app and release archive contain matching translations for {len(english)} keys', flush=True)

probe = OUT / 'LocalizationTests.app'
if probe.exists():
    shutil.rmtree(probe)
binary = probe / 'Contents/MacOS/LocalizationTests'
binary.parent.mkdir(parents=True)
resources = probe / 'Contents/Resources'
resources.mkdir()
for language in ('en', 'zh-Hans'):
    shutil.copytree(APP / 'Contents/Resources' / f'{language}.lproj', resources / f'{language}.lproj')
info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
assert info['CFBundleDevelopmentRegion'] == 'en'
assert info['CFBundleLocalizations'] == ['en', 'zh-Hans']
info.update(CFBundleIdentifier='local.zjf.curtain.localization-tests', CFBundleExecutable='LocalizationTests')
(probe / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['xcrun', 'swiftc', '-Osize', '-whole-module-optimization', '-module-cache-path', str(ROOT / 'build/module-cache'),
                '-framework', 'AppKit', '-framework', 'Security', 'Sources/App/AppVersion.swift',
                'Sources/App/UpdatePackage.swift', 'Sources/App/PermissionGuide.swift',
                'Tests/LocalizationTests.swift', '-o', str(binary)], cwd=ROOT, check=True)
for requested, expected in [('en', 'en'), ('zh-Hans', 'zh-Hans'), ('fr', 'en')]:
    subprocess.run([str(binary), expected, '-AppleLanguages', f'({requested})'], check=True, timeout=30)
