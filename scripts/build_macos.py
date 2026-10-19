"""Build a self-contained native macOS app. Uses only Apple's command-line tools + Node."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
APP = BUILD / 'Dayproof.app'
CONTENTS = APP / 'Contents'
RESOURCES = CONTENTS / 'Resources'
BACKEND = RESOURCES / 'backend'

def run(*args, cwd=ROOT):
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)

if os.uname().sysname != 'Darwin':
    raise SystemExit('The native app currently builds on macOS only.')
run('npm', 'run', 'build')
CONTENTS.joinpath('MacOS').mkdir(parents=True, exist_ok=True)
BACKEND.mkdir(parents=True, exist_ok=True)
# Ship the same Node runtime whose ABI the SQLite module was built against.
node = Path(shutil.which('node')).resolve()
shutil.copy2(node, RESOURCES / 'node')
os.chmod(RESOURCES / 'node', 0o755)
for entry in ['index', 'mcp']:
    run(ROOT / 'node_modules/.bin/esbuild', ROOT / f'src/server/{entry}.ts', '--bundle',
        '--platform=node', '--format=esm', '--packages=external', f'--outfile={BACKEND / (entry + ".mjs")}')
shutil.copy2(ROOT / 'package.json', BACKEND / 'package.json')
shutil.copy2(ROOT / 'package-lock.json', BACKEND / 'package-lock.json')
# Production dependencies only. Dependencies and their licenses stay together.
run('npm', 'ci', '--omit=dev', '--no-audit', '--no-fund', cwd=BACKEND)
shutil.copytree(ROOT / 'dist', BACKEND / 'dist', dirs_exist_ok=True)
shutil.copy2(ROOT / 'native/Resources/migrate.mjs', BACKEND / 'migrate.mjs')
for f in ['LICENSE', 'README.md', 'THIRD_PARTY_NOTICES.md']:
    shutil.copy2(ROOT / f, RESOURCES / f)
shutil.copytree(ROOT / 'native/Vendor', RESOURCES / 'ThirdParty', dirs_exist_ok=True)
shutil.copy2(ROOT / 'native/Vendor/Node/LICENSE', RESOURCES / 'Node-LICENSE')
(RESOURCES / 'bootstrap.json').write_text(json.dumps({
    'legacyData': str(ROOT / 'data'), 'evidenceRoot': str(ROOT)
}))
plist = {
    'CFBundleName': 'Dayproof', 'CFBundleDisplayName': 'Dayproof',
    'CFBundleIdentifier': 'app.dayproof.desktop', 'CFBundleExecutable': 'Dayproof',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.2.0',
    'CFBundleVersion': '2', 'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
    'NSHumanReadableCopyright': 'Dayproof contributors. MIT. Includes AgentPet MIT components.',
}
with (CONTENTS / 'Info.plist').open('wb') as f:
    plistlib.dump(plist, f)
sources = sorted((ROOT / 'native/Sources').glob('*.swift')) + [ROOT / 'native/Vendor/AgentPet/SpriteSlicer.swift']
run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-parse-as-library',
    '-target', os.uname().machine + '-apple-macosx13.0', *sources,
    '-o', CONTENTS / 'MacOS/Dayproof', '-framework', 'AppKit', '-framework', 'SwiftUI')
# Ad hoc signing is sufficient for this locally built application; not notarization.
run('codesign', '--force', '--sign', '-', RESOURCES / 'node')
run('codesign', '--force', '--deep', '--sign', '-', APP)
print(f'\nBuilt {APP}\nLaunch: npm run desktop')
