# Windows public beta website

The maintainer approved an unsigned public Windows beta on 2026-10-17 after the SignPath application was declined. Signing is not a release prerequisite for this beta. The existing macOS release and signed updater remain unchanged.

## Release configuration

- Version: `0.7.0-beta.9`
- GitHub prerelease tag: `windows-v0.7.0-beta.9`; do not mark it latest or replace the stable macOS release.
- Installer: `https://github.com/tobymarks/inlaut/releases/download/windows-v0.7.0-beta.9/inlaut-0.7.0-beta.9-windows-x64-setup.exe`
- Landing pages: `/windows` and `/en/windows`, linked throughout both language sites. Only these pages link directly to the EXE, so visitors see the unsigned-beta notice before downloading.
- Download event: `download-windows`, with version `0.7.0-beta.9` and position `windows-download`.

## Published guidance

The warning is immediately above the download and referenced by its accessible description. It explains that the beta is unsigned and Windows SmartScreen may warn or show an unknown publisher. Installation steps offer “More info” → “Run anyway” only if those options are offered, after deliberately downloading the official installer. Smart App Control or organisation policies can block installation; users are not told to disable security protections.

Windows 10/11 x64, German or English dictation and independently selectable UI language are listed. The page states that Windows 11 acceptance testing is incomplete and names quiet speech, recording boundaries, spacing/capitalisation between dictations and application-specific insertion as beta limitations. Mixed-language dictation, Apple speech recognition, Apple Intelligence corrections and file transcription remain scoped to macOS.

Updates are manual through the website; quit inlaut before installing. The signed in-app updater cannot install this unsigned beta. Do not deploy a Windows update manifest or weaken signature verification. The app can still make manual or opted-in update checks, so the privacy page retains this network disclosure.

## Publication sequence

1. Build and validate the release installer and accompanying checksums from the release commit.
2. Publish the GitHub prerelease and verify the exact installer URL and checksum before deploying the site.
3. Validate the German and English download notices, local links, JSON-LD, FAQ content and desktop/mobile layouts. Regenerate home-page FAQ JSON-LD with `python3 scripts/sync-faq-schema.py` after FAQ edits.
4. Deploy with `cd site && npx wrangler deploy`, then verify the live landing pages and download URL. Do not publish a Windows update feed for unsigned assets.

The website source includes the active links; deployment and GitHub publication must be verified separately. macOS download links, release assets and signed release notes are preserved.
