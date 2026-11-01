#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Xcode and Apple SDKs are required on a Mac. This script does not create a placeholder IPA.' >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'An Apple macOS build host is required.' >&2
  exit 2
fi
xcodebuild -version
xcodebuild -showsdks
mkdir -p build
case "${1:-simulator}" in
  simulator)
    xcodebuild -project BlackBox.xcodeproj -scheme BlackBox -configuration Debug \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
    ;;
  unsigned)
    xcodebuild -project BlackBox.xcodeproj -scheme BlackBox -configuration Release \
      -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
    app_path='build/DerivedData/Build/Products/Release-iphoneos/BlackBox.app'
    test -x "$app_path/BlackBox"
    /usr/bin/file "$app_path/BlackBox"
    /usr/bin/xcrun lipo -verify_arch arm64 "$app_path/BlackBox"
    /usr/bin/xcrun vtool -show-build "$app_path/BlackBox"
    staging="$(mktemp -d "$PWD/build/ipa.XXXXXX")"
    trap 'rm -rf "$staging"' EXIT
    mkdir -p "$staging/Payload"
    ditto "$app_path" "$staging/Payload/BlackBox.app"
    (cd "$staging" && /usr/bin/zip -qry BlackBox-0.1.0-unsigned.ipa Payload)
    python3 Scripts/verify-ipa.py "$staging/BlackBox-0.1.0-unsigned.ipa"
    mv -f "$staging/BlackBox-0.1.0-unsigned.ipa" build/BlackBox-0.1.0-unsigned.ipa
    (cd build && shasum -a 256 BlackBox-0.1.0-unsigned.ipa > BlackBox-0.1.0-unsigned.ipa.sha256)
    echo 'Created build/BlackBox-0.1.0-unsigned.ipa. It must be re-signed by SideStore; device installation is unverified.'
    ;;
  *) echo 'Usage: Scripts/build-ios.sh [simulator|unsigned]' >&2; exit 2 ;;
esac
