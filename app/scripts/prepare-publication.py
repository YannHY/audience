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
UPDATES = APP / 'build/travail/updates'
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
    archive_source = APP / 'build/travail/TestFlight/Audience-iPad.xcarchive'
    with (APP / 'Resources/Info-iPad.plist').open('rb') as stream:
        ipad_info = plistlib.load(stream)
    with (archive_source / 'Info.plist').open('rb') as stream:
        archived = plistlib.load(stream)['ApplicationProperties']
    with (archive_source / 'Products/Applications/Audience-iPad.app/Info.plist').open('rb') as stream:
        bundled_ipad = plistlib.load(stream)
    for candidate in (ipad_info, archived, bundled_ipad):
        assert (candidate['CFBundleShortVersionString'], candidate['CFBundleVersion']) == (version, build), 'Version iPad obsolète'
    assert bundled_ipad['CFBundleIdentifier'] == 'fr.audience.native.ipad', 'Identifiant iPad inattendu'
    export_source = APP / 'build/travail/TestFlight/Export'
    ipa_source = export_source / 'Audience.ipa'
    if ipa_source.is_file():
        with zipfile.ZipFile(ipa_source) as archive:
            exported = plistlib.loads(archive.read('Payload/Audience-iPad.app/Info.plist'))
        assert (exported['CFBundleShortVersionString'], exported['CFBundleVersion']) == (version, build), 'IPA iPad obsolète'
        assert exported['CFBundleIdentifier'] == 'fr.audience.native.ipad', 'Identifiant IPA inattendu'
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
    archive_target = ipad / 'Audience-iPad.xcarchive'
    # iCloud can add FinderInfo to loose bundles and invalidate their signature.
    # Keep the handoff sealed in a ZIP prepared outside iCloud instead.
    if archive_target.is_dir():
        shutil.rmtree(archive_target)
    with tempfile.TemporaryDirectory(prefix='audience-testflight-package-') as temporary:
        staged = Path(temporary) / 'Audience-iPad.xcarchive'
        subprocess.run(['ditto', '--norsrc', '--noextattr', str(archive_source), str(staged)], check=True)
        subprocess.run(['xattr', '-cr', str(staged)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(staged / 'Products/Applications/Audience-iPad.app')], check=True)
        subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr',
                        str(staged), str(ipad / 'Audience-iPad.xcarchive.zip')], check=True)
    copy(APP / 'Resources/ExportOptions-TestFlight.plist', ipad / 'ExportOptions-TestFlight.plist')
    if ipa_source.is_file():
        for filename in ('Audience.ipa', 'DistributionSummary.plist', 'ExportOptions.plist'):
            copy(export_source / filename, ipad / 'Export-AppStoreConnect' / filename)
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
    # Keep only the current handoff beside the app; never discard an older release.
    for previous in sorted((APP / 'build').glob('Publication-*')):
        if previous.is_dir() and previous != destination:
            archived = APP / 'build/archives' / previous.name
            if archived.exists():
                raise FileExistsError(f'Archive déjà présente : {archived}')
            archived.parent.mkdir(parents=True, exist_ok=True)
            previous.rename(archived)
    # A copy of mac/ at the site root mirrors /apps/audience/mac/ on the server, ready to drag and drop.
    server_mac = SITE / 'mac'
    if server_mac.exists():
        shutil.rmtree(server_mac)
    shutil.copytree(mac, server_mac, ignore=shutil.ignore_patterns('.*'))
    # Rebuilding the source ZIP must also refresh the handoff's integrity manifest.
    checksums = destination / 'SHA256SUMS.txt'
    files = sorted(path for path in destination.rglob('*')
                   if path.is_file() and path != checksums
                   and not any(part.startswith('.') for part in path.relative_to(destination).parts))
    checksums.write_text(''.join(f'{digest(path)}  {path.relative_to(destination).as_posix()}\n' for path in files))
    print(destination)


if __name__ == '__main__':
    main()
