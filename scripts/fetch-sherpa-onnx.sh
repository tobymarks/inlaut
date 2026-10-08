#!/bin/bash
# Downloads the pinned sherpa-onnx C API (Apache-2.0, bundles onnxruntime, MIT)
# into Vendor/sherpa-onnx and checks it against a known SHA-256.
set -euo pipefail

VERSION=1.13.8
NAME=sherpa-onnx-v$VERSION-osx-arm64-shared-no-tts-lib
SHA256=f3e0cbd86cc3f38dad30c97921b40e9a8bcc6f2c943777eb76ad77176993e417
HEADER_SHA256=2a1b95084be8fd1deb3228fcad2fd3f7f0258b64582f7402281ec174c7b7f4ce

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Vendor/sherpa-onnx"
[ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ] && exit 0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sSfL -o "$TMP/lib.tar.bz2" "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$VERSION/$NAME.tar.bz2"
echo "$SHA256  $TMP/lib.tar.bz2" | shasum -a 256 -c - >/dev/null
tar -xjf "$TMP/lib.tar.bz2" -C "$TMP"

rm -rf "$DEST" && mkdir -p "$DEST/lib" "$DEST/include"
cp "$TMP/$NAME/lib/libsherpa-onnx-c-api.dylib" "$TMP/$NAME/lib/libonnxruntime.dylib" "$DEST/lib/"
curl -sSfL -o "$DEST/include/c-api.h" \
  "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v$VERSION/sherpa-onnx/c-api/c-api.h"
echo "$HEADER_SHA256  $DEST/include/c-api.h" | shasum -a 256 -c - >/dev/null
cat > "$DEST/include/module.modulemap" <<'MAP'
module SherpaOnnx {
    header "c-api.h"
    link "sherpa-onnx-c-api"
    export *
}
MAP
echo "$VERSION" > "$DEST/.version"
echo "sherpa-onnx $VERSION ready in Vendor/sherpa-onnx"
