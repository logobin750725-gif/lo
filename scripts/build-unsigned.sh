#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -version
xcodebuild -project DualAI.xcodeproj -scheme DualAI -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build | tee build/xcodebuild.log
app="$PWD/build/DerivedData/Build/Products/Release-iphoneos/DualAI.app"
test -f "$app/DualAI"
test -f "$app/Info.plist"
test -f "$app/Web/index.html"
file "$app/DualAI" | tee build/binary-info.txt
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist"
mkdir -p build/package/Payload
ditto "$app" build/package/Payload/DualAI.app
ditto -c -k --keepParent build/package/Payload build/DualAI-unsigned.ipa
unzip -t build/DualAI-unsigned.ipa
shasum -a 256 build/DualAI-unsigned.ipa | tee build/SHA256.txt
echo 'Unsigned IPA built. Sign it before installation; this is not an App Store archive.'
