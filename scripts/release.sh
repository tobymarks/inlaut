#!/bin/bash
# Builds a Developer ID archive, notarizes/staples it, then signs the update feed.
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
    "$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
      --download-url-prefix "https://github.com/tobymarks/inlaut/releases/download/v$VERSION/" \
      --link https://inlaut.de --embed-release-notes "$STAGING"
    "$TOOLS/sign_update" --account "$ACCOUNT" --verify "$STAGING/appcast.xml"
    # Ensure the signed feed actually points at the package we are about to publish.
    python3 scripts/validate-appcast.py "$STAGING/appcast.xml" "$STAGING/$NAME" "$APP"
    (cd "$STAGING" && shasum -a 256 "$NAME" > SHA256SUMS)
    echo "Ready for review: $STAGING"
    echo 'Upload the ZIP to a GitHub Release first; deploy this appcast only after the asset is public.'
    ;;
  *) echo "Usage: $0 {prepare|notarize|package}" >&2; exit 2 ;;
esac
