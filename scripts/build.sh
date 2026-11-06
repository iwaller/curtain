#!/bin/zsh
# Builds the menu bar app (build/Curtain.app) and the experiment CLI (build/curtain-poc).
# Signs with the first "Apple Development" identity when there is one, so macOS privacy
# permissions (Accessibility) survive rebuilds; falls back to ad-hoc. Override: CURTAIN_SIGN_IDENTITY.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
swiftc_common=(xcrun swiftc -module-cache-path build/module-cache)

identity=${CURTAIN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')}
identity=${identity:--}

$swiftc_common -framework AppKit Sources/Shared/*.swift Sources/POC/main.swift -o build/curtain-poc

app=build/Curtain.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
$swiftc_common -framework AppKit -framework IOKit -framework ApplicationServices \
  Sources/Shared/*.swift Sources/App/*.swift -o "$app/Contents/MacOS/Curtain"
cp Resources/Info.plist "$app/Contents/Info.plist"
# Layered Liquid Glass icon (Icon Composer format) -> Assets.car for macOS 26+, Curtain.icns for older systems.
mkdir -p "$app/Contents/Resources"
xcrun actool "$PWD/Resources/Curtain.icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon Curtain \
  --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null
codesign --force --timestamp=none --sign "$identity" "$app" >/dev/null
print "Built build/curtain-poc and $app (signed: $identity)"
