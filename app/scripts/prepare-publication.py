#!/usr/bin/env python3
"""Assemble only the Mac download/update folder and the local TestFlight handoff."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from urllib.parse import unquote, urlparse

APP = Path(__file__).resolve().parents[1]
SITE = APP.parent
UPDATES = APP / 'build/updates'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
PUBLIC = 'https://www.ralentirtravaux.com/apps/audience/mac/'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(source, target)


def main():
    with (APP / 'Resources/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    name = f'Audience-{version}-{build}'
    destination = APP / 'build' / f'Publication-{version}-{build}'
    mac = destination / 'mac'
    mac.mkdir(parents=True, exist_ok=True)
    feed = ET.parse(UPDATES / 'appcast.xml')
    items = feed.findall('./channel/item')
    assert items and items[0].findtext(SPARKLE + 'version') == build, 'Flux obsolète'
    artifacts = set()
    for item in items:
        for enclosure in item.iter('enclosure'):
            url = enclosure.attrib['url']
            assert url.startswith(PUBLIC), f'URL inattendue : {url}'
            filename = unquote(urlparse(url).path.rsplit('/', 1)[1])
            assert filename == Path(filename).name and filename not in ('', '.', '..')
            source = UPDATES / filename
            assert source.is_file() and source.stat().st_size == int(enclosure.attrib['length']), filename
            assert enclosure.attrib.get(SPARKLE + 'edSignature'), f'Signature absente : {filename}'
            copy(source, mac / filename)
            artifacts.add(filename)
        for note in item.findall(SPARKLE + 'releaseNotesLink'):
            assert note.text.startswith(PUBLIC)
            filename = unquote(urlparse(note.text).path.rsplit('/', 1)[1])
            copy(UPDATES / filename, mac / filename)
    latest = f'{name}-macOS.zip'
    assert latest in artifacts
    with zipfile.ZipFile(mac / latest) as archive:
        bundled = plistlib.loads(archive.read('Audience.app/Contents/Info.plist'))
    assert bundled['CFBundleVersion'] == build and bundled['CFBundleShortVersionString'] == version
    assert bundled['SUFeedURL'] == PUBLIC + 'appcast.xml'
    assert bundled['SUPublicEDKey'] == info['SUPublicEDKey']
    copy(mac / latest, mac / 'Audience-macOS.zip')
    assert digest(mac / latest) == digest(mac / 'Audience-macOS.zip')
    copy(UPDATES / 'appcast.xml', mac / 'appcast.xml')

    # Ship corresponding native sources using an explicit allowlist, never local data or credentials.
    source_zip = mac / f'{name}-sources.zip'
    source_files = [SITE / 'LICENSE', SITE / 'LICENSE-CONTENT.txt', SITE / 'README.md',
                    APP / 'README.md', APP / 'Package.swift', APP / 'Package.resolved',
                    APP / 'Audience.xcodeproj/project.pbxproj']
    for directory in ['Sources', 'Tests', 'Resources', 'scripts', 'Audience.xcodeproj/xcshareddata']:
        source_files.extend(p for p in (APP / directory).rglob('*')
                            if p.is_file() and not any(part.startswith('.') or part == '__pycache__'
                                                     for part in p.relative_to(APP).parts))
    with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(set(source_files)):
            if source.exists():
                archive.write(source, 'Audience-source/' + str(source.relative_to(SITE)))

    ipad = destination / 'iPad-TestFlight'
    ipad.mkdir(parents=True, exist_ok=True)
    archive_source = APP / 'build/TestFlight/Audience-iPad.xcarchive'
    archive_target = ipad / 'Audience-iPad.xcarchive'
    # iCloud can add FinderInfo to loose bundles and invalidate their signature.
    # Keep the handoff sealed in a ZIP prepared outside iCloud instead.
    if archive_target.is_dir():
        shutil.rmtree(archive_target)
    with tempfile.TemporaryDirectory(prefix='audience-testflight-package-') as temporary:
        staged = Path(temporary) / 'Audience-iPad.xcarchive'
        subprocess.run(['ditto', '--norsrc', '--noextattr', str(archive_source), str(staged)], check=True)
        subprocess.run(['xattr', '-cr', str(staged)], check=True)
        subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr',
                        str(staged), str(ipad / 'Audience-iPad.xcarchive.zip')], check=True)
    copy(APP / 'Resources/ExportOptions-TestFlight.plist', ipad / 'ExportOptions-TestFlight.plist')
    finalize = ipad / 'Finaliser-export.command'
    finalize.write_text('''#!/bin/zsh
set -euo pipefail
DIST_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/audience-testflight-export.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto -x -k "$DIST_DIR/Audience-iPad.xcarchive.zip" "$STAGE_DIR"
xcodebuild -exportArchive -archivePath "$STAGE_DIR/Audience-iPad.xcarchive" \\
  -exportPath "$DIST_DIR/Export-AppStoreConnect" \\
  -exportOptionsPlist "$DIST_DIR/ExportOptions-TestFlight.plist" \\
  -allowProvisioningUpdates
printf '\\nExport terminé. Aucun téléversement ni invitation TestFlight n’a été effectué.\\n'
''')
    finalize.chmod(finalize.stat().st_mode | stat.S_IXUSR)
    print(destination)


if __name__ == '__main__':
    main()
