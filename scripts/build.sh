#!/bin/zsh
# Builds the menu bar app (build/Curtain.app) and the experiment CLI (build/curtain-poc).
# Signs with the first "Apple Development" identity when there is one, so macOS privacy
# permissions (Accessibility) survive rebuilds; falls back to ad-hoc. Override: CURTAIN_SIGN_IDENTITY.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
# Supported: macOS 15 and later (keep in sync with LSMinimumSystemVersion in Resources/Info.plist).
min_macos=15.0
swiftc_common=(xcrun swiftc -module-cache-path build/module-cache -target "$(uname -m)-apple-macos$min_macos")

identity=${CURTAIN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')}
identity=${identity:--}

$swiftc_common -framework AppKit Sources/Shared/*.swift Sources/POC/main.swift -o build/curtain-poc

app=build/Curtain.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
$swiftc_common -framework CoreGraphics Sources/Watchdog/*.swift -o "$app/Contents/Helpers/CurtainWatchdog"
codesign --force --timestamp=none --sign "$identity" "$app/Contents/Helpers/CurtainWatchdog" >/dev/null
$swiftc_common -framework AppKit -framework IOKit -framework ApplicationServices \
  Sources/Shared/*.swift Sources/App/*.swift -o "$app/Contents/MacOS/Curtain"
cp Resources/Info.plist "$app/Contents/Info.plist"
# Layered Liquid Glass icon (Icon Composer format) -> Assets.car for macOS 26+, Curtain.icns for macOS 15.
mkdir -p "$app/Contents/Resources"
xcrun actool "$PWD/Resources/Curtain.icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target "$min_macos" --app-icon Curtain \
  --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null
codesign --force --timestamp=none --sign "$identity" "$app" >/dev/null
print "Built build/curtain-poc and $app (signed: $identity)"
