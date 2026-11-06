#!/bin/zsh
# Create a compressed, read-only drag-to-Applications image from the signed app.
set -euo pipefail
cd "${0:A:h:h}"
app=build/Curtain.app
if [[ ! -d "$app" ]]; then
    print -u2 "Run ./scripts/build.sh first."
    exit 1
fi
codesign --verify --deep --strict "$app"
for executable in "$app/Contents/MacOS/Curtain" "$app/Contents/Helpers/CurtainWatchdog"; do
    if [[ $(xcrun lipo -archs "$executable") != arm64 ]]; then
        print -u2 "Curtain releases require arm64-only app and watchdog binaries. Rebuild first."
        exit 1
    fi
done
staging=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$staging"' EXIT
volume="$staging/volume"
mkdir "$volume"
ditto "$app" "$volume/Curtain.app"
ln -s /Applications "$volume/Applications"
codesign --verify --deep --strict "$volume/Curtain.app"
hdiutil create -volname Curtain -srcfolder "$volume" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 "$staging/Curtain.dmg" >/dev/null
hdiutil verify "$staging/Curtain.dmg" >/dev/null
mv -f "$staging/Curtain.dmg" build/Curtain-arm64.dmg
print "Built build/Curtain-arm64.dmg (open the image and drag Curtain to Applications)."
