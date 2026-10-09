#!/usr/bin/env python3
"""Validate release metadata without modifying the signed appcast bytes."""
import base64
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

feed, archive, app = map(Path, sys.argv[1:])
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(feed).findall('./channel/item')
item = next((item for item in items if item.findtext('s:version', namespaces=ns) == info['CFBundleVersion']), None)
if item is None:
    sys.exit('Appcast has no entry for the current build.')
enc = item.find('enclosure')
expected = f"https://github.com/tobymarks/inlaut/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
if enc is None or enc.get('url') != expected:
    sys.exit('Unexpected download URL in appcast.')
if int(enc.get('length', '0')) != archive.stat().st_size:
    sys.exit('Archive length does not match appcast.')
signature = enc.get(f"{{{ns['s']}}}edSignature", '')
if len(base64.b64decode(signature, validate=True)) != 64:
    sys.exit('Missing or invalid Ed25519 archive signature.')
if item.findtext('s:minimumSystemVersion', namespaces=ns) != info['LSMinimumSystemVersion']:
    sys.exit('Minimum macOS version differs from the app.')
# Per-language release notes are links; Sparkle verifies them against the
# signature, so every staged notes file needs a signed link in the feed.
links = {link.get('{http://www.w3.org/XML/1998/namespace}lang'): link
         for link in item.findall('s:releaseNotesLink', namespaces=ns)}
for notes in sorted(archive.parent.glob(f"{archive.stem}.??.html")):
    language = notes.stem.rsplit('.', 1)[1]
    link = links.get(language)
    if link is None or link.text.strip() != f"https://inlaut.de/updates/notes/{notes.name}":
        sys.exit(f'Missing or wrong release notes link for {language}.')
    if int(link.get(f"{{{ns['s']}}}length", '0')) != notes.stat().st_size or not link.get(f"{{{ns['s']}}}edSignature"):
        sys.exit(f'Release notes for {language} are not signed.')
print(f"Appcast metadata valid for {archive.name} (build {info['CFBundleVersion']}).")
