#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
xcodebuild -project "$repo/Riff.xcodeproj" -scheme Riff -sdk iphoneos \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$repo/artifacts/ipad-build" CODE_SIGNING_ALLOWED=NO build
staging="$(mktemp -d "${TMPDIR:-/tmp}/riff-ipa.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
ditto "$repo/artifacts/ipad-build/Build/Products/Release-iphoneos/Riff.app" "$staging/Payload/Riff.app"
ditto -c -k --keepParent "$staging/Payload" "$repo/artifacts/Riff-iPad-unsigned.ipa"
echo "Created artifacts/Riff-iPad-unsigned.ipa. Sign with your own Apple account before installation."
