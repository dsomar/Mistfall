#!/bin/zsh
# Test build of the standalone app only (dist-test/Mistfall-App.zip). The released dist/ is not touched,
# and the app carries the screen saver already released in dist/, not a new one.
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
[[ -z "$IDENTITY" ]] && { echo "No Developer ID Application cert found"; exit 1; }
xcodegen generate >/dev/null
xcodebuild -scheme Mistfall -configuration Release -derivedDataPath /tmp/MistfallBuild \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" build | grep -E "error:|BUILD"
P=/tmp/MistfallBuild/Build/Products/Release
OUT=dist-test
rm -rf $OUT && mkdir $OUT
cp -R $P/Mistfall.app $OUT/
rm -rf $OUT/Mistfall.app/Contents/Resources/Mistfall.saver
rm -rf /tmp/mf-old-saver && mkdir /tmp/mf-old-saver && ditto -x -k dist/Mistfall-Screensaver.zip /tmp/mf-old-saver
cp -R /tmp/mf-old-saver/Mistfall.saver $OUT/Mistfall.app/Contents/Resources/
codesign --force --options runtime --timestamp --sign "$IDENTITY" $OUT/Mistfall.app
codesign --verify --deep --strict --verbose=2 $OUT/Mistfall.app
ditto -c -k --keepParent $OUT/Mistfall.app $OUT/upload.zip
xcrun notarytool submit $OUT/upload.zip --keychain-profile mistfall --wait
rm $OUT/upload.zip
xcrun stapler staple $OUT/Mistfall.app
spctl -a -t exec -vv $OUT/Mistfall.app
ditto -c -k --keepParent $OUT/Mistfall.app $OUT/Mistfall-App.zip
echo "Done: $(pwd)/$OUT/Mistfall-App.zip"
