#!/bin/zsh
# Build, sign, notarize and staple Mistfall for free distribution outside the App Store:
#   dist/Mistfall-Screensaver.zip  the screen saver on its own (Mistfall.saver)
#   dist/Mistfall-App.zip          the standalone app (Mistfall.app), which also carries
#                                  the screen saver for its "Install as Screen Saver" menu
# Prereqs: "Developer ID Application" cert in keychain; notarytool profile "mistfall".
# The current dist/ is only replaced once everything has been approved.
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
[[ -z "$IDENTITY" ]] && { echo "No Developer ID Application cert found"; exit 1; }
echo "Signing with: $IDENTITY"
xcodegen generate >/dev/null
xcodebuild -scheme Mistfall -configuration Release -derivedDataPath /tmp/MistfallBuild \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" build | grep -E "error:|BUILD"
P=/tmp/MistfallBuild/Build/Products/Release
OUT=dist.new
rm -rf $OUT && mkdir $OUT

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"; codesign --verify --deep --strict --verbose=2 "$1"; }
notarize() {  # bundle, name
  ditto -c -k --keepParent "$1" "$OUT/$2-upload.zip"
  xcrun notarytool submit "$OUT/$2-upload.zip" --keychain-profile mistfall --wait
  rm "$OUT/$2-upload.zip"
  xcrun stapler staple "$1"
}

echo "== Screen saver"
cp -R $P/Mistfall.saver $OUT/
sign $OUT/Mistfall.saver
notarize $OUT/Mistfall.saver saver
spctl -a -t install -vv $OUT/Mistfall.saver

echo "== App"
cp -R $P/Mistfall.app $OUT/
# Carry the approved screen saver inside the app, so the copy it installs works offline too.
rm -rf $OUT/Mistfall.app/Contents/Resources/Mistfall.saver
cp -R $OUT/Mistfall.saver $OUT/Mistfall.app/Contents/Resources/
sign $OUT/Mistfall.app
notarize $OUT/Mistfall.app app
spctl -a -t exec -vv $OUT/Mistfall.app

ditto -c -k --keepParent $OUT/Mistfall.saver $OUT/Mistfall-Screensaver.zip
ditto -c -k --keepParent $OUT/Mistfall.app $OUT/Mistfall-App.zip
rm -rf dist.old; [[ -d dist ]] && mv dist dist.old
mv $OUT dist && rm -rf dist.old
echo "Done: $(pwd)/dist/Mistfall-Screensaver.zip and Mistfall-App.zip"
