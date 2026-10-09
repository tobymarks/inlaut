#!/bin/bash
# Builds a notarized app, drag-to-install DMG and signed Sparkle ZIP/feed.
# No credentials or private keys are read into shell variables or repository files.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-prepare}"
PROFILE="${NOTARY_PROFILE:-Inlaut}"
ACCOUNT="de.tobymarks.inlaut"
OUT="$ROOT/build/release"
TOOLS="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
APP="$OUT/export/Inlaut.app"

case "$MODE" in
  prepare)
    scripts/fetch-sherpa-onnx.sh
    xcodegen generate
    mkdir -p "$OUT"
    xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Release \
      -destination 'generic/platform=macOS' -derivedDataPath build \
      -clonedSourcePackagesDirPath build/SourcePackages \
      -archivePath "$OUT/Inlaut.xcarchive" archive
    xcodebuild -exportArchive -archivePath "$OUT/Inlaut.xcarchive" \
      -exportPath "$OUT/export" -exportOptionsPlist "$ROOT/Resources/ExportOptions.plist"
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign --display --verbose=4 "$APP"
    echo "Signed app: $APP"
    echo "Next: NOTARY_PROFILE=$PROFILE scripts/release.sh notarize"
    ;;
  notarize)
    test -d "$APP" || { echo 'Run scripts/release.sh prepare first.' >&2; exit 1; }
    # Check credentials before packaging/submitting. Authentication stays in Keychain.
    xcrun notarytool history --keychain-profile "$PROFILE" --output-format json > "$OUT/notary-history.json"
    /usr/bin/ditto -c -k --keepParent "$APP" "$OUT/notarization.zip"
    xcrun notarytool submit "$OUT/notarization.zip" --keychain-profile "$PROFILE" \
      --wait --output-format json > "$OUT/notarization.json"
    python3 - "$OUT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit(f"Notarization not accepted: {result.get('status')}; submission {result.get('id')}")
print(f"Notarization accepted: {result['id']}")
PY
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    "$0" package
    ;;
  package)
    # Refuse to generate a distributable/feed for an unnotarized app.
    xcrun stapler validate "$APP"
    codesign --verify --deep --strict "$APP"
    VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
    BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
    STAGING="$OUT/updates/$VERSION-$BUILD_NUMBER"
    mkdir -p "$STAGING"
    # Keep existing entries and their GitHub URLs when publishing the next release.
    cp site/public/updates/appcast.xml "$STAGING/appcast.xml"
    NAME="Inlaut-$VERSION.zip"
    /usr/bin/ditto -c -k --keepParent "$APP" "$STAGING/$NAME"
    if [ -f "release-notes/$VERSION.html" ]; then
      cp "release-notes/$VERSION.html" "$STAGING/Inlaut-$VERSION.html"
    fi
    # Per-language notes (<version>.de.html, <version>.en.html) become signed
    # links with xml:lang; Sparkle shows the one matching the app's language.
    # They are served from inlaut.de/updates/notes/ next to the feed.
    for LANGUAGE in de en; do
      if [ -f "release-notes/$VERSION.$LANGUAGE.html" ]; then
        cp "release-notes/$VERSION.$LANGUAGE.html" "$STAGING/Inlaut-$VERSION.$LANGUAGE.html"
      fi
    done
    "$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
      --download-url-prefix "https://github.com/tobymarks/inlaut/releases/download/v$VERSION/" \
      --release-notes-url-prefix "https://inlaut.de/updates/notes/" \
      --link https://inlaut.de --embed-release-notes "$STAGING"
    "$TOOLS/sign_update" --account "$ACCOUNT" --verify "$STAGING/appcast.xml"
    # Ensure the signed feed actually points at the package we are about to publish.
    python3 scripts/validate-appcast.py "$STAGING/appcast.xml" "$STAGING/$NAME" "$APP"
    (cd "$STAGING" && shasum -a 256 "$NAME" > SHA256SUMS)
    "$0" dmg
    echo "Sparkle update: $STAGING"
    echo 'Upload the DMG and ZIP to GitHub before deploying the download link and signed appcast.'
    if ls "$STAGING"/Inlaut-"$VERSION".??.html >/dev/null 2>&1; then
      echo "Copy $STAGING/Inlaut-$VERSION.<lang>.html unchanged to site/public/updates/notes/ together with the feed."
    fi
    ;;
  dmg)
    # Can also add a DMG to an existing release without rewriting its ZIP/feed.
    xcrun stapler validate "$APP"
    codesign --verify --deep --strict "$APP"
    VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
    BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
    DMG_OUT="$OUT/downloads/$VERSION-$BUILD_NUMBER"
    mkdir -p "$DMG_OUT"
    VENV="$ROOT/build/dmg-venv"
    if [ ! -x "$VENV/bin/python" ]; then python3 -m venv "$VENV"; fi
    "$VENV/bin/python" -m pip install --disable-pip-version-check -r scripts/dmg-requirements.txt
    # German image for inlaut.de, English one (-en) for inlaut.de/en/.
    for LANGUAGE in de en; do
      if [ "$LANGUAGE" = en ]; then SUFFIX="-en"; FOLDER="Applications"; else SUFFIX=""; FOLDER="Programme"; fi
      BASE="Inlaut-$VERSION$SUFFIX"
      DMG="$DMG_OUT/$BASE.dmg"
      # A published image is never replaced; a missing language can still be added.
      if [ -e "$DMG" ]; then echo "Keeping existing release image: $DMG"; continue; fi
      xcrun swift scripts/render-dmg-background.swift "$DMG_OUT/artwork-$LANGUAGE" "$LANGUAGE"
      # Keep incomplete images separate from the final, publishable filename.
      PENDING="$DMG_OUT/$BASE.pending.dmg"
      "$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D "app=$APP" -D "folder=$FOLDER" \
        -D "background=$DMG_OUT/artwork-$LANGUAGE/background.png" 'inlaut' "$PENDING"
      "$VENV/bin/python" scripts/validate-dmg.py "$PENDING" "$APP" "$FOLDER"
      IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Tobias Marks (7V4K87652E)}"
      codesign --force --sign "$IDENTITY" --timestamp "$PENDING"
      codesign --verify --strict "$PENDING"
      xcrun notarytool submit "$PENDING" --keychain-profile "$PROFILE" \
        --wait --output-format json > "$DMG_OUT/notarization-$LANGUAGE.json"
      python3 - "$DMG_OUT/notarization-$LANGUAGE.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit(f"DMG notarization not accepted: {result.get('status')}; submission {result.get('id')}")
print(f"DMG notarization accepted: {result['id']}")
PY
      xcrun stapler staple "$PENDING"
      xcrun stapler validate "$PENDING"
      spctl --assess --type open --context context:primary-signature --verbose=2 "$PENDING"
      mv "$PENDING" "$DMG"
      (cd "$DMG_OUT" && shasum -a 256 "$BASE.dmg" > "$BASE.dmg.sha256")
      echo "Notarized installer: $DMG"
    done
    echo 'Publish both DMGs and their .sha256 files; retain the ZIP and signed feed for Sparkle updates.'
    ;;
  *) echo "Usage: $0 {prepare|notarize|package|dmg}" >&2; exit 2 ;;
esac
